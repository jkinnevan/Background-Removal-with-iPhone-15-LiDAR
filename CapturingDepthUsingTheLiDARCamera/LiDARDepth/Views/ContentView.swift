import SwiftUI
import MetalKit
import Metal
import Combine
import Foundation
import AVFoundation
import Photos


struct ContentView: View {
    
    @StateObject private var manager = CameraManager()
    @StateObject private var orientationObserver = OrientationObserver()
    @StateObject private var cancellableHolder = CancellableHolder() // Define cancellableHolder as a StateObject
    @StateObject private var cameraController = CameraController()
    
    // Variable bound to user interface objects
    @State private var exposureValue: Float = 1.0
    @State private var minDepthSlider: Float = 4.0
    @State private var rollOffSlider: Float = 0.0
    @State private var redSaturation: Float = 1.0
    @State private var greenSaturation: Float = 1.0
    @State private var blueSaturation: Float = 1.0
    @State private var isBackgroundControlOn: Bool = false
    @State private var videoRecorder: VideoRecorder?
    @State private var isRecording = false
    @State private var edgeSlider: Float = 3.5
    
    // Variable holding the FPS data output to the digital display
    @State private var fps: Double = 0.0 // Added by Jessica Kinnevan for FPS
    
    // Store subscriptions (fpr FPS) - Added by Jessica Kinnevan
    private var cancellables = Set<AnyCancellable>()
    
    let maxRangeDepth = Float(15)
    let minRangeDepth = Float(0)
    
    // Condigure UI object positions
    var body: some View {
        ZStack { // Use ZStack as the outermost container
            
            // Video content to take up most of the screen
            MetalTextureViewColor(
                //rotationAngle: self.rotationAngle(for: orientationObserver.orientation),
                rotationAngle: 0,
                capturedData: manager.capturedData,
                exposureValue: $exposureValue,
                minDepthSlider: $minDepthSlider,
                redSaturation: $redSaturation,
                greenSaturation: $greenSaturation,
                blueSaturation: $blueSaturation,
                isBackgroundControlOn: $isBackgroundControlOn,
                isRecording: $isRecording,
                rollOffSlider: $rollOffSlider,
                edgeSlider: $edgeSlider
            )
            .aspectRatio(3/4, contentMode: .fit)
            
            // Display FPS on screen
            VStack {

                
                VStack {
                    SliderDepthBoundaryView(val: $minDepthSlider, label: "Depth", minVal: 0.0, maxVal: 4.0)
                    SliderDepthBoundaryView(val: $rollOffSlider, label: "Rolloff", minVal: 0.00, maxVal: 1.0)
                    SliderDepthBoundaryView(val: $edgeSlider, label: "kernel", minVal: 0.00, maxVal: 10.0)
                    
                    HStack{
                        Text("CPU FPS: \(String(format: "%.2f", fps))")
                            .foregroundColor(.white)
                            .padding(5)
                            .background(Color.black.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding()
                        Spacer()
                        
                    }
                    // Push controls to the top and sliders to the bottom
                    Spacer()
                     
                    HStack{
                        Toggle("", isOn: $isBackgroundControlOn)
                        Spacer()
                    }
                    // Exposure and color correction sliders
                    SliderDepthBoundaryView(val: $exposureValue, label: "Exposure", minVal: 0, maxVal: 3)
                    SliderDepthBoundaryView(val: $redSaturation, label: "RedSaturation", minVal: 0, maxVal: 2)
                    SliderDepthBoundaryView(val: $greenSaturation, label: "greenSaturation", minVal: 0, maxVal: 2)
                    SliderDepthBoundaryView(val: $blueSaturation, label: "blueSaturation", minVal: 0, maxVal: 2)
                }
            }
            .onAppear {
                // Subscribe to FPS updates when the view appears
                manager.fpsPublisher
                    .receive(on: RunLoop.main)
                    .sink { newFPS in // Removed [weak self]
                        fps = newFPS
                    }
                    .store(in: &cancellableHolder.cancellables)
            }
        }
    }
    
    // This was put in place for future the recoding feature that had to be removed
    private func toggleRecording() {
            isRecording.toggle()
            if isRecording {
                // Assuming cameraController is an instance of CameraController
                cameraController.startRecording()
            } else {
                cameraController.stopRecording()
            }
        }
    
    
    struct SliderDepthBoundaryView: View {
        @Binding var val: Float
        var label: String
        var minVal: Float
        var maxVal: Float
        let stepsCount = Float(200.0)
        var body: some View {
            HStack {
                Text(String(format: " %@: %.2f", label, val))
                Slider(
                    value: $val,
                    in: minVal...maxVal,
                    step: (maxVal - minVal) / stepsCount
                ) {
                } minimumValueLabel: {
                    Text(String(minVal))
                } maximumValueLabel: {
                    Text(String(maxVal))
                }
            }
        }
    }
    
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
                .previewDevice("iPhone 15 Pro Max")
        }
    }
}

// Added for FPS
class CancellableHolder: ObservableObject {
    var cancellables = Set<AnyCancellable>()
}

class OrientationObserver: ObservableObject {
    @Published var orientation: UIDeviceOrientation = .portrait // Default to portrait
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.publisher(for: UIDevice.orientationDidChangeNotification)
            .map { _ in UIDevice.current.orientation }
            .assign(to: \.orientation, on: self)
            .store(in: &cancellables)
    }
}
// The code below was put in place for recording the streaming viedo to file.
// This feature has been removed as it was not ready in time for the deadline

class VideoRecorder {
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    init?(outputURL: URL, size: CGSize) {
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: size.width,
                AVVideoHeightKey: size.height
            ]
            assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            assetWriterVideoInput?.expectsMediaDataInRealTime = true

            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: assetWriterVideoInput!,
                sourcePixelBufferAttributes: nil
            )

            if assetWriter!.canAdd(assetWriterVideoInput!) {
                assetWriter!.add(assetWriterVideoInput!)
            } else {
                return nil
            }
        } catch {
            print("Unable to initialize AVAssetWriter: \(error)")
            return nil
        }
    }

    func startRecording() {
        assetWriter?.startWriting()
        assetWriter?.startSession(atSourceTime: .zero)
    }

    func writeFrame(pixelBuffer: CVPixelBuffer, at time: CMTime) {
        if assetWriterVideoInput!.isReadyForMoreMediaData {
            pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: time)
        }
    }

    func finishRecording(completion: @escaping () -> Void) {
        assetWriterVideoInput?.markAsFinished()
        assetWriter?.finishWriting(completionHandler: completion)
    }
}

