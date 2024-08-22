/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An object that configures and manages the capture pipeline to stream video and LiDAR depth data.
*/

import Foundation
import AVFoundation
import CoreImage
import Accelerate // Used for image format conversion - JK
import MetalKit // Used for getting Instrinsic info - JK
import Metal // Used for getting Instrinsic info - JK
import CoreMedia // Jessica Kinnevan
import Combine // Jessica
import Photos

protocol CaptureDataReceiver: AnyObject {
    func onNewData(capturedData: CameraCapturedData)
    func onNewPhotoData(capturedData: CameraCapturedData)
    // New function added for FPS display by Jessica Kinnevan
    // ensures that any class conforming to this protocol will have to implement a
    // method to handle FPS updates, which is a clean way to communicate FPS data.
    func updateFPS(fps: Double)

}

class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate,  AVCaptureMetadataOutputObjectsDelegate{
    
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var isRecording = false
    
    enum ConfigurationError: Error {
        case lidarDeviceUnavailable
        case requiredFormatUnavailable
    }
    
    private let preferredWidthResolution = 1920
    
    private let videoQueue = DispatchQueue(label: "com.example.apple-samplecode.VideoQueue", qos: .userInteractive)
    
    private(set) var captureSession: AVCaptureSession!
    
    private var photoOutput: AVCapturePhotoOutput!
    private var depthDataOutput: AVCaptureDepthDataOutput!
    private var videoDataOutput: AVCaptureVideoDataOutput!
    private var outputVideoSync: AVCaptureDataOutputSynchronizer!
    private var imageCounter = 0 // Jessica Kinnevan
    private var lastFrameTimestamp: CMTime? // Jessica Kinnevan
    
    private var textureCache: CVMetalTextureCache!
    
    weak var delegate: CaptureDataReceiver?
    
    var isFilteringEnabled = true {
        didSet {
            depthDataOutput.isFilteringEnabled = isFilteringEnabled
        }
    }
    
    override init() {
        
        // Create a texture cache to hold sample buffer textures.
        CVMetalTextureCacheCreate(kCFAllocatorDefault,
                                  nil,
                                  MetalEnvironment.shared.metalDevice,
                                  nil,
                                  &textureCache)
        
        super.init()
        
        do {
            try setupSession()
        } catch {
            fatalError("Unable to configure the capture session.")
        }
        // Set self as the sample buffer delegate - Jessica Kinnevan
        videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)
    }
    
    // Make sure you update the image counter to prevent overwriting existing files
    
    private func updateImageCounter() {
        let fileManager = FileManager.default
        do {
            let documentsDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let directoryContents = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            
            let imageFiles = directoryContents.filter { $0.pathExtension == "jpg" && $0.lastPathComponent.starts(with: "CameraImage_") }
            
            let fileIndices = imageFiles.compactMap { url -> Int? in
                let filename = url.deletingPathExtension().lastPathComponent
                let parts = filename.components(separatedBy: "_")
                return parts.count > 1 ? Int(parts[1]) : nil
            }
            
            if let maxIndex = fileIndices.max() {
                self.imageCounter = maxIndex + 1
            }
        } catch {
            print("Error reading contents of documents directory: \(error)")
        }
    }
    
    // Add setup for face detection - Jessica Kinnevan
    private func setupFaceDetection() {
        let metadataOutput = AVCaptureMetadataOutput()

        if self.captureSession.canAddOutput(metadataOutput) {
            self.captureSession.addOutput(metadataOutput)

            // Set this object as the delegate to process the metadata objects.
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)

            // Set the metadata object types to face.
            metadataOutput.metadataObjectTypes = [.face]
        } else {
            print("Could not add metadata output for face detection.")
        }
    }
    
    private func setupSession() throws {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .inputPriority

        // Configure the capture session.
        captureSession.beginConfiguration()
        
        try setupCaptureInput()
        setupCaptureOutputs()
        setupFaceDetection() // Added this line to setup face detection - Jessica Kinnevan
        
        // Finalize the capture session configuration.
        captureSession.commitConfiguration()
        print("captureSession.commitConfiguration()")
    }
    
    private func setupCaptureInput() throws {
        // Look up the LiDAR camera.
        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            throw ConfigurationError.lidarDeviceUnavailable
        }
        
        // Find a match that outputs video data in the format the app's custom Metal views require.
        guard let format = (device.formats.last { format in
            format.formatDescription.dimensions.width == preferredWidthResolution &&
            format.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange &&
            !format.isVideoBinned &&
            !format.supportedDepthDataFormats.isEmpty
        }) else {
            throw ConfigurationError.requiredFormatUnavailable
        }
        
        // Find a match that outputs depth data in the format the app's custom Metal views require.
        guard let depthFormat = (format.supportedDepthDataFormats.last { depthFormat in
            depthFormat.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_DepthFloat16
        }) else {
            throw ConfigurationError.requiredFormatUnavailable
        }

        
        // Begin the device configuration.
        try device.lockForConfiguration()

        device.activeFormat = format
        device.activeDepthDataFormat = depthFormat

        // Finish the device configuration.
        device.unlockForConfiguration()
        
        // Add a device input to the capture session.
        let deviceInput = try AVCaptureDeviceInput(device: device)
        captureSession.addInput(deviceInput)
    }
    
    private func setupCaptureOutputs() {
        print("setupCaptureOutputs called")
        // Create an object to output video sample buffers.
        videoDataOutput = AVCaptureVideoDataOutput()
        //videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        
        // Set CameraController as the sample buffer delegate - Jessica Kinnevan
        //videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
                captureSession.addOutput(videoDataOutput)
                
                // Now that the output is added, you can check the connection
                if let connection = videoDataOutput.connection(with: .video) {
                    if connection.isActive {
                        print("requestAccess")
                    } else {
                        print("Video connection is not active")
                    }
                } else {
                    print("No video connection")
                }
                
        }
        else {
                print("Could not add video data output to the session")
        }
        
        // Create an object to output depth data.
        depthDataOutput = AVCaptureDepthDataOutput()
        depthDataOutput.isFilteringEnabled = isFilteringEnabled
        captureSession.addOutput(depthDataOutput)

        // Create an object to synchronize the delivery of depth and video data.
        outputVideoSync = AVCaptureDataOutputSynchronizer(dataOutputs: [depthDataOutput, videoDataOutput])
        outputVideoSync.setDelegate(self, queue: videoQueue)
        
        // Create an object to output photos.
        photoOutput = AVCapturePhotoOutput()
        photoOutput.maxPhotoQualityPrioritization = .quality
        captureSession.addOutput(photoOutput)

        // Enable delivery of depth data after adding the output to the capture session.
        photoOutput.isDepthDataDeliveryEnabled = true
    }
    
    // Put video capture session in background thread.
    func startStream() {
        print("startStream called")
        videoQueue.async { [weak self] in
            guard let self = self else { return } // Check if self is not nil
            self.updateImageCounter()  // Ensure we're starting with the correct image counter - JK
            self.captureSession.startRunning() // No need for try because startRunning() does not throw
         
        }
    }

    func stopStream() {
        print("stopStream called")
        videoQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
    

    func prepareAssetWriter(with pixelBuffer: CVPixelBuffer, at timestamp: CMTime) {
        print("prepareAssetWriter called")
        let videoWidth = CVPixelBufferGetWidth(pixelBuffer)
        let videoHeight = CVPixelBufferGetHeight(pixelBuffer)
        let outputUrl = FileManager.default.temporaryDirectory.appendingPathComponent("outputVideo.mp4")
        setupVideoWriter(outputUrl: outputUrl, size: CGSize(width: videoWidth, height: videoHeight))

        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: timestamp)

        if assetWriter?.status != .writing {
                if let error = assetWriter?.error {
                    print("Failed to start asset writer with error: \(error)")
                } else {
                    print("Asset writer status unknown or not writing.")
                }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("captureOutput called")
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer.")
            return
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Check if recording should start and assetWriter is nil
        if isRecording && assetWriter == nil {
            print("Starting asset writer.")
            prepareAssetWriter(with: pixelBuffer, at: presentationTime)
        }

        // Append the pixel buffer to the asset writer if it's ready for more data
        if isRecording, let adaptor = pixelBufferAdaptor, adaptor.assetWriterInput.isReadyForMoreMediaData {
            // Append the pixel buffer at the correct presentation time
            if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                print("Failed to append pixel buffer")
            }
        }
    }






}

// MARK: AVCaptureMetadataOutputObjectsDelegate for Face Detection - Jessica Kinnevan
extension CameraController {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // Process metadata objects for face detection
        guard !metadataObjects.isEmpty else { return }
        
        // Example: Calculate the average position of detected faces and adjust exposure
        // This code snippet assumes you have a method to calculate and adjust the exposure based on face positions
        let faces = metadataObjects.compactMap { $0 as? AVMetadataFaceObject }
        guard let firstFace = faces.first else { return }
        
        let faceBounds = firstFace.bounds
        let faceCenterPoint = CGPoint(x: faceBounds.midX, y: faceBounds.midY)
        
        // Convert the face center point from the metadataOutput's coordinate system to the device's coordinate system
        DispatchQueue.main.async {
            //guard let strongSelf = self, let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            do {
                try captureDevice.lockForConfiguration()
                
                if captureDevice.isExposurePointOfInterestSupported {
                    captureDevice.exposurePointOfInterest = faceCenterPoint
                    print("faceCenterPoint: \(faceCenterPoint)");
                    captureDevice.exposureMode = .continuousAutoExposure
                }
                
                captureDevice.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
        
    }
}

// MARK: Output Synchronizer Delegate
extension CameraController: AVCaptureDataOutputSynchronizerDelegate {
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        // Retrieve the synchronized depth and sample buffer container objects.
        guard let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
              let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else { return }
        
        // Calculate the frame rate based on the sample buffer timestamps -Jessica Kinnevan.
        calculateFPS(from: syncedVideoData.sampleBuffer)
        
        guard let pixelBuffer = syncedVideoData.sampleBuffer.imageBuffer,
              let cameraCalibrationData = syncedDepthData.depthData.cameraCalibrationData else { return }
        
        // Package the captured data.
        let data = CameraCapturedData(depth: syncedDepthData.depthData.depthDataMap.texture(withFormat: .r16Float, planeIndex: 0, addToCache: textureCache),
                                      colorY: pixelBuffer.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache),
                                      colorCbCr: pixelBuffer.texture(withFormat: .rg8Unorm, planeIndex: 1, addToCache: textureCache),
                                      cameraIntrinsics: cameraCalibrationData.intrinsicMatrix,
                                      cameraReferenceDimensions: cameraCalibrationData.intrinsicMatrixReferenceDimensions)
        
        delegate?.onNewData(capturedData: data)
    }
    
    private func calculateFPS(from sampleBuffer: CMSampleBuffer) {
        // Retrieve the presentation timestamp of the current frame from the sampleBuffer
        let currentFrameTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if let lastTimestamp = lastFrameTimestamp {
            let elapsedTime = CMTimeGetSeconds(currentFrameTimestamp) - CMTimeGetSeconds(lastTimestamp)
            if elapsedTime > 0 {
                let fps = 1.0 / elapsedTime
                //print("Current FPS: \(fps)") // Print the calculated FPS
                DispatchQueue.main.async {
                    self.delegate?.updateFPS(fps: fps)
                }
            } else {
                print("Elapsed time is zero or negative") // Indicate a potential issue
            }
        } else {
            print("This is the first frame")
        }
        
        lastFrameTimestamp = currentFrameTimestamp
    }
    

}


// MARK: Photo Capture Delegate
extension CameraController: AVCapturePhotoCaptureDelegate {
    
    func capturePhoto() {
        var photoSettings: AVCapturePhotoSettings
        if  photoOutput.availablePhotoPixelFormatTypes.contains(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            photoSettings = AVCapturePhotoSettings(format: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ])
        } else {
            photoSettings = AVCapturePhotoSettings()
        }
        
        // Capture depth data with this photo capture.
        photoSettings.isDepthDataDeliveryEnabled = true
        photoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        // Retrieve the image and depth data.
        guard let pixelBuffer = photo.pixelBuffer,
              let depthData = photo.depthData,
              let cameraCalibrationData = depthData.cameraCalibrationData else { return }
        
        // Stop the stream until the user returns to streaming mode.
        stopStream()
        
        // Convert the depth data to the expected format.
        let convertedDepth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat16)
        
        // Package the captured data.
        let data = CameraCapturedData(depth: convertedDepth.depthDataMap.texture(withFormat: .r16Float, planeIndex: 0, addToCache: textureCache),
                                      colorY: pixelBuffer.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache),
                                      colorCbCr: pixelBuffer.texture(withFormat: .rg8Unorm, planeIndex: 1, addToCache: textureCache),
                                      cameraIntrinsics: cameraCalibrationData.intrinsicMatrix,
                                      cameraReferenceDimensions: cameraCalibrationData.intrinsicMatrixReferenceDimensions)
        
        delegate?.onNewPhotoData(capturedData: data)
        
        guard let imageData = photo.fileDataRepresentation(),
                  let depthData = photo.depthData?.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap else {
                print("Error: Unable to get image or depth data")
        
                return
        }
            
        // Save the image data as before
        saveDataToFile(data: imageData, withFileName: "CameraImage")
        saveDataToBinFile(data: imageData, withFileName: "CapturedBinaryImage")
        
        // Extract and save the depth data
        if let depthValues = extractDepthData(from: depthData) {
            saveDepthDataToFile(depthValues: depthValues, withFileName: "LiDARDepthData")
        }
        imageCounter += 1
        
        // Camera intrinsic parameters
        let cameraIntrinsics: matrix_float3x3 = cameraCalibrationData.intrinsicMatrix // This should be your actual camera intrinsic matrix
        let scaleRes: SIMD2<Float> = simd_float2(x: Float(data.cameraReferenceDimensions.width) / Float(data.depth?.width ?? 1),
                                                 y: Float(data.cameraReferenceDimensions.height) / Float(data.depth!.height)) // This should be your actual scale factors
    
        
        
        

        // Created by Team 7 to save the camera intrinsic information for 3D renderings of the depth data.
        var intrinsicDataString = "Camera Intrinsic Matrix:\n"
        for i in 0..<3 {
            intrinsicDataString += "\(cameraIntrinsics[i][0] / scaleRes.x) \(cameraIntrinsics[i][1] / scaleRes.y) \(cameraIntrinsics[i][2] / scaleRes.x)\n"
        }

        // Get the path to the documents directory
        let fileManager = FileManager.default
        if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileName = "camera_intrinsics.txt"
            let fileURL = documentsDirectory.appendingPathComponent(fileName)
            
            // Write the string to a file
            do {
                try intrinsicDataString.write(to: fileURL, atomically: true, encoding: .utf8)
                print("Successfully saved intrinsics to \(fileURL.path)")
            } catch {
                print("Error saving intrinsics: \(error)")
            }
        }
        
    }
    
    // Created by Team 7 to save a single image as a .jpg with a file number that increments from the
    // existing photos in the App folder. This and two depth data can be downloaded from the iTunes
    // Files tab within the app. This feature was disabled from the user interfcae to focus on the
    // live video data.
    private func saveDataToFile(data: Data, withFileName fileName: String) {
        let fileManager = FileManager.default
        do {
            let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)

            let fullFileName = "\(fileName)_\(imageCounter).jpg" // Incorporate the image counter into the filename
            let fileURL = documentDirectory.appendingPathComponent(fullFileName)
            
            try data.write(to: fileURL, options: .atomic)
            print("File saved: \(fileURL)")
        } catch {
            print("Error saving file: \(error)")
        }
    }
    
    // Created by Team 7 to save the image as a binary file. This format was never used in a meaningful way.
    private func saveDataToBinFile(data: Data, withFileName fileName: String) {
        let fileManager = FileManager.default
        do {
            // Get the URL for the document directory
            let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            // Create a file URL for the new file in the document directory
            let fullFileName = "\(fileName)_\(imageCounter).bin" // Incorporate the image counter into the filename - JK
            let fileURL = documentDirectory.appendingPathComponent(fullFileName)
            
            // Write the binary data to the file
            try data.write(to: fileURL, options: .atomic)
            print("Binary file saved: \(fileURL)")
        } catch {
            print("Error saving binary file: \(error)")
        }
    }
    
    // Created by Team 7 to save depth data from the image capture feature for photos
    // that was disabled when streaming with image processing was enabled.
    // The function stores binary depth data to the App folder that can be downloaded
    // from the Files tab in iTunes. It assigned a file number that corresponds with the
    // color photo taken at the same time.
    func saveDepthDataToFile(depthValues: [Float], withFileName fileName: String) {
        let fileManager = FileManager.default
        do {
            let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            // Create a file URL for the new file in the document directory
            //let fullFileName = "\(fileName)_\(imageCounter).bin" // Incorporate the image counter into the filename -JK
            let fileURL = documentDirectory.appendingPathComponent("\(fileName)_\(imageCounter).bin")
            
            // Directly create Data from the array of Floats
            let data = Data(bytes: depthValues, count: depthValues.count * MemoryLayout<Float>.size)
            try data.write(to: fileURL, options: .atomic)
            print("Depth data file saved: \(fileURL)")
        } catch {
            print("Error saving depth data file: \(error)")
        }
    }

    
    func extractDepthData(from pixelBuffer: CVPixelBuffer) -> [Float]? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        
        var depthValues = [Float]()
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for row in 0..<height {
            let rowData = baseAddress.advanced(by: row * rowBytes).assumingMemoryBound(to: Float.self)
            for col in 0..<width {
                depthValues.append(rowData[col])
            }
        }
        
        return depthValues
    }
    
}

// MARK: - Exposure Adjustment for Detected Faces - Team 7 - Jessica Kinnevan, Toral Chauhan, Naifa Alqahtani
extension CameraController {
    func adjustExposureForDetectedFaces(metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) else {
            print("Device does not support exposure adjustments based on faces.")
            return
        }

        // Calculate the average center of all detected faces
        let faces = metadataObjects.compactMap { $0 as? AVMetadataFaceObject }
        guard !faces.isEmpty else { return }
        
        let convertedFaces = faces.compactMap { faceObject -> CGRect? in
            return self.videoDataOutput.transformedMetadataObject(for: faceObject, connection: connection)?.bounds
        }
        
        guard !convertedFaces.isEmpty else { return }
        
        let averageFaceCenter = convertedFaces.reduce(CGPoint.zero) { (current, faceRect) -> CGPoint in
            CGPoint(x: current.x + faceRect.midX, y: current.y + faceRect.midY)
        }
        
        let finalPoint = CGPoint(x: averageFaceCenter.x / CGFloat(convertedFaces.count), y: averageFaceCenter.y / CGFloat(convertedFaces.count))
        
        DispatchQueue.main.async {
                    do {
                        try device.lockForConfiguration()
                        
                        // Set the exposure to the average face center...
                        device.exposurePointOfInterest = finalPoint
                        device.exposureMode = .continuousAutoExposure
                        
                        device.unlockForConfiguration()
                    } catch {
                        print("Could not lock device for configuration: \(error)")
                    }
                }
    }
}

// Below are functions created by Team 7 for saving the streaming video to the camera roll, but the
// feature was never fully implemented

extension CameraController {
    func startRecording() {
        // Ensure no ongoing recording
        guard !isRecording else {
            print("Recording is already in progress.")
            return
        }
        // Set the recording flag
        isRecording = true
        print("recording started")
        // Check and request permissions if necessary
        requestAuthorizationIfNeeded()
        
    }

    func stopRecording() {
        guard let writer = assetWriter, writer.status == .writing else {
            print("Attempted to stop recording but asset writer was not in writing state or recording wasn't started.")
            return
        }

        isRecording = false
        assetWriterInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            if let self = self, writer.status == .completed {
                print("Video file creation completed successfully.")
                self.saveVideoToCameraRoll(outputUrl: writer.outputURL)
            } else if let error = writer.error {
                print("Failed to complete video writing with error: \(error)")
            }
        }
    }

    func writeFrameToVideo(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        if pixelBufferAdaptor?.assetWriterInput.isReadyForMoreMediaData ?? false {
            pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: timestamp)
        }
    }
    private func setupVideoWriter(outputUrl: URL, size: CGSize) {
        // Define the video settings dictionary using the size parameters passed to the function
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264.rawValue,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]

        do {
            // Initialize the AVAssetWriter with the output URL and mp4 file type
            assetWriter = try AVAssetWriter(outputURL: outputUrl, fileType: .mp4)
            // Create the AVAssetWriterInput with video media type and the settings dictionary
            assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            assetWriterInput?.expectsMediaDataInRealTime = true

            // Configure the pixel buffer attributes for the asset writer input
            let sourcePixelBufferAttributes: [String: Any] = [
                (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32ARGB),
                (kCVPixelBufferWidthKey as String): size.width,
                (kCVPixelBufferHeightKey as String): size.height,
                (kCVPixelBufferMetalCompatibilityKey as String): true
            ]

            // Initialize the pixel buffer adaptor with the asset writer input and the attributes dictionary
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: assetWriterInput!,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )

            // Add the asset writer input to the asset writer
            if let writer = assetWriter, let input = assetWriterInput, writer.canAdd(input) {
                writer.add(input)
            }
        } catch {
            print("Could not create AVAssetWriter: \(error)")
        }
    }

    private func saveVideoToCameraRoll(outputUrl: URL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputUrl)
        }, completionHandler: { success, error in
            if success {
                print("Video saved successfully to camera roll")
            } else {
                print("Could not save video to camera roll: \(String(describing: error))")
            }
        })
    }
    
    func requestAuthorizationIfNeeded() {
        PHPhotoLibrary.requestAuthorization { status in
            switch status {
            case .authorized:
                print("Authorization granted by the user")
                // proceed with saving video
            case .denied, .restricted, .limited:
                print("Authorization denied or restricted")
            case .notDetermined:
                print("Authorization not determined")
            @unknown default:
                fatalError("Unknown authorization status")
            }
        }
    }
}
