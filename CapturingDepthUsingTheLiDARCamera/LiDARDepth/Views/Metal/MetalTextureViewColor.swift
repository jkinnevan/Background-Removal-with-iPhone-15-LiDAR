/*
 COM S 575 (Spring 2024 - Iowa State University)
 Project by Jessica Kinnevan, Toral Chauhan, Naifa Alqahtani
 
 This render pipeline configuration file was orginally a part of a sample code project provided by Apple called
 "Capturing depth using the LiDAR camera"
 
 Available here:
 https://developer.apple.com/documentation/avfoundation/additional_data_capture/capturing_depth_using_the_lidar_camera
 
 Most of the original code was removed or altered. The original code used a single shader and pipeline descriptor with RGB and
 depth data. This code uses 2 shaders, one of which (planeFragmentShaderRemoveBackground) generates and intermediate texture with the alpha set based on the depth threshold. This intermediate texture is pass an an input to the second shader as well and uses different variables bound to user interface slider.
*/

import SwiftUI
import MetalKit
import Metal
import CoreVideo // Jessica Kinnevan

struct MetalTextureViewColor: UIViewRepresentable, MetalRepresentable {
    var rotationAngle: Double
    var capturedData: CameraCapturedData
    
    // Incoming variables bound to user interface sliders
    @Binding var exposureValue: Float
    @Binding var minDepthSlider: Float
    @Binding var redSaturation: Float
    @Binding var greenSaturation: Float
    @Binding var blueSaturation: Float
    @Binding var isBackgroundControlOn: Bool
    @Binding var isRecording: Bool
    @Binding var rollOffSlider: Float
    @Binding var edgeSlider: Float
    
    func makeCoordinator() -> MTKColorTextureCoordinator {
        MTKColorTextureCoordinator(parent: self)
    }
}

final class MTKColorTextureCoordinator: MTKCoordinator<MetalTextureViewColor> {
    
    // Declare backgroundTexture for hold the background replacement image
    var backgroundTexture: MTLTexture?
    
    // Declare two pipeline descriptors, one for each shader.
    var pipelineDescriptor: MTLRenderPipelineDescriptor?
    var pipelineDescriptor2: MTLRenderPipelineDescriptor?
    
    // Configure the render pipeline for two RGBA outputs of bgra8Unorm type and one
    // depth map of type depth32Float
    override func preparePipelineAndDepthState() {
        guard let metalDevice = mtkView.device else { fatalError("Expected a Metal device.") }
        do {
            
            backgroundTexture = loadBackgroundTexture(device: metalDevice)
            if backgroundTexture == nil {
                fatalError("Failed to load the background texture")
            }
            
            let library = MetalEnvironment.shared.metalLibrary
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            
            pipelineDescriptor.vertexFunction = library.makeFunction(name: "planeVertexShader")
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: "planeFragmentShaderRemoveBackground")
            pipelineDescriptor.vertexDescriptor = createPlaneMetalVertexDescriptor()
            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
            
            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.isDepthWriteEnabled = true
            depthDescriptor.depthCompareFunction = .less
            depthState = metalDevice.makeDepthStencilState(descriptor: depthDescriptor)
            
            
            let pipelineDescriptor2 = MTLRenderPipelineDescriptor()
            pipelineDescriptor2.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            pipelineDescriptor2.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor2.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor2.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor2.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor2.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor2.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor2.colorAttachments[0].alphaBlendOperation = .add
            
            pipelineDescriptor2.vertexFunction = library.makeFunction(name: "planeVertexShader")
            pipelineDescriptor2.fragmentFunction = library.makeFunction(name: "planeFragmentShaderConvolution")
            pipelineDescriptor2.vertexDescriptor = createPlaneMetalVertexDescriptor()
            secondPipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor2)
            
            
        } catch {
            print("Unexpected error: \(error).")
        }
    }
    
    
    // Load the background image as a texture from the app assets to use between Shader 1 (planeFragmentShaderRemoveBackground)
    // and Shader 2 (planeFragmentShaderRemoveBackground).
    private func loadBackgroundTexture(device: MTLDevice) -> MTLTexture? {
        guard let image = UIImage(named: "backgroundImage"), let cgImage = image.cgImage else {
            print("Failed to load background image")
            return nil
        }
        let textureLoader = MTKTextureLoader(device: device)
        do {
            let textureOptions: [MTKTextureLoader.Option: Any] = [.origin: MTKTextureLoader.Origin.bottomLeft]
            return try textureLoader.newTexture(cgImage: cgImage, options: textureOptions)
        } catch {
            print("Error loading texture: \(error)")
            return nil
        }
    }
    
    // Define the intermediate texture to be used to store the output of Shader 1 (planeFragmentShaderRemoveBackground)
    // and used as the input of Shader 2 (planeFragmentShaderRemoveBackground).
    // The shader is of type bgra8Unorm and will pass an RGBA image with the background removed,
    // and any foreground color and exposure corrections, as well as the rolloff applied to the alpha channel
    func createIntermediateTexture(using device: MTLDevice, for view: MTKView, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: Int(view.drawableSize.width),
            height: Int(view.drawableSize.height),
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        textureDescriptor.storageMode = .private
        
        return device.makeTexture(descriptor: textureDescriptor)
    }
    
    // Confgure render pass encoding:
    // 1. Check for availability of Y, CbCr, and depth data
    // 2. Create a command buffer
    // 3. Texture configuration
    // 4. Render pass configuration
    // 5. Configure buffers that pass UI and other data to GPU
    override func draw(in view: MTKView) {
        
        guard parent.capturedData.colorY != nil && parent.capturedData.colorCbCr != nil else {
            print("There's no content to display.")
            return
        }
        
        guard let colorYTexture = parent.capturedData.colorY,
              let colorCbCrTexture = parent.capturedData.colorCbCr,
              let depthTexture2 = parent.capturedData.depth else {
              //let drawable = view.currentDrawable
            print("There's no content to display.")
            return
        }
        
        guard let commandBuffer = metalCommandQueue.makeCommandBuffer() else { return }
        // Create and configure the intermediate texture
        guard let metalDevice = mtkView.device,
              let intermediateTexture = createIntermediateTexture(using: metalDevice, for: view) else {
            print("Failed to create intermediate texture.")
            return
        }
                
        let depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: Int(view.drawableSize.width),
            height: Int(view.drawableSize.height),
            mipmapped: false)
        depthTextureDescriptor.usage = [.shaderRead, .shaderWrite, .renderTarget] // Ensure shader read usage is set
        depthTextureDescriptor.storageMode = .private

        let depthTexture = metalDevice.makeTexture(descriptor: depthTextureDescriptor)
        //let depthTexture = parent.capturedData.depth
        
        
        // First Pass: Render to intermediate texture
        let firstPassDescriptor = MTLRenderPassDescriptor()
        firstPassDescriptor.colorAttachments[0].texture = intermediateTexture
        firstPassDescriptor.colorAttachments[0].loadAction = .clear
        firstPassDescriptor.colorAttachments[0].storeAction = .store
        firstPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
    
     
        firstPassDescriptor.depthAttachment.texture = depthTexture
        firstPassDescriptor.depthAttachment.loadAction = .clear
        firstPassDescriptor.depthAttachment.storeAction = .store
        firstPassDescriptor.depthAttachment.clearDepth = 1.0
        
        // Proceed with creating the encoder using the non-optional descriptor
        guard let firstEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: firstPassDescriptor)  else {
            print("Failed to create first pass encoder.")
            return
        }

        let vertexData: [Float] = [-1, -1, 1, 1,
                                    1, -1, 1, 0,
                                   -1,  1, 0, 1,
                                    1,  1, 0, 0]
        
        firstEncoder.setVertexBytes(vertexData, length: vertexData.count * MemoryLayout<Float>.stride, index: 0)
        firstEncoder.setFragmentTexture(colorYTexture, index: 0)
        firstEncoder.setFragmentTexture(colorCbCrTexture, index: 1)
        firstEncoder.setFragmentTexture(depthTexture2, index: 2)
        var exposureAdjustment: Float = parent.exposureValue
        firstEncoder.setFragmentBytes(&exposureAdjustment, length: MemoryLayout<Float>.size, index: 0)
        var depthAdjustment: Float = parent.minDepthSlider
        firstEncoder.setFragmentBytes(&depthAdjustment, length: MemoryLayout<Float>.size, index: 1)
        var redAdjustment: Float = parent.redSaturation
        firstEncoder.setFragmentBytes(&redAdjustment, length: MemoryLayout<Float>.size, index: 2)
        var greenAdjustment: Float = parent.greenSaturation
        firstEncoder.setFragmentBytes(&greenAdjustment, length: MemoryLayout<Float>.size, index: 3)
        var blueAdjustment: Float = parent.blueSaturation
        firstEncoder.setFragmentBytes(&blueAdjustment, length: MemoryLayout<Float>.size, index: 4)
        var isBackgroundCntlOn: Bool = parent.isBackgroundControlOn
        firstEncoder.setFragmentBytes(&isBackgroundCntlOn, length: MemoryLayout<Float>.size, index: 5)
        var rollOff: Float = parent.rollOffSlider
        firstEncoder.setFragmentBytes(&rollOff, length: MemoryLayout<Float>.size, index: 6)
        firstEncoder.setDepthStencilState(depthState)
        firstEncoder.setRenderPipelineState(pipelineState)
        firstEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        firstEncoder.endEncoding()
        
        
        guard let drawable = mtkView.currentDrawable else {
            fatalError("Current drawable is nil.")
        }

        let secondPassDescriptor = MTLRenderPassDescriptor()
        secondPassDescriptor.colorAttachments[0].texture = drawable.texture
        secondPassDescriptor.colorAttachments[0].loadAction = .clear  // Clear the framebuffer (optional based on desired visual result)
        secondPassDescriptor.colorAttachments[0].storeAction = .store  // Ensure rendered content is stored to be presented to the screen
        secondPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)  // Clear color, can be adjusted as needed
        

        let vertexData2: [Float] = [
            -1, -1, 0, 1,  // Bottom-left vertex, top-right texture
             1, -1, 1, 1,  // Bottom-right vertex, top-left texture
            -1,  1, 0, 0,  // Top-left vertex, bottom-right texture
             1,  1, 1, 0   // Top-right vertex, bottom-left texture
        ]
        
        guard let secondEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: secondPassDescriptor) else {
            print("Failed to create secondEncoder.")
            return
        }
        secondEncoder.setRenderPipelineState(secondPipelineState) // Use the second pipeline state
        secondEncoder.setVertexBytes(vertexData2, length: vertexData2.count * MemoryLayout<Float>.stride, index: 0)
        secondEncoder.setFragmentTexture(intermediateTexture, index: 0)
        secondEncoder.setFragmentTexture(backgroundTexture, index: 1)
        secondEncoder.setFragmentBytes(&exposureAdjustment, length: MemoryLayout<Float>.size, index: 0)
        secondEncoder.setFragmentBytes(&redAdjustment, length: MemoryLayout<Float>.size, index: 1)
        secondEncoder.setFragmentBytes(&greenAdjustment, length: MemoryLayout<Float>.size, index: 2)
        secondEncoder.setFragmentBytes(&blueAdjustment, length: MemoryLayout<Float>.size, index: 3)
        secondEncoder.setFragmentBytes(&isBackgroundCntlOn, length: MemoryLayout<Float>.size, index: 4)
        var edgeSlide: Float = parent.edgeSlider // Edge slider only used for kernel adjustment in second shader
        secondEncoder.setFragmentBytes(&edgeSlide, length: MemoryLayout<Float>.size, index: 5)
        secondEncoder.setRenderPipelineState(secondPipelineState)
        secondEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        secondEncoder.endEncoding()
        
        // Present the drawable and commit the command buffer
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
 
