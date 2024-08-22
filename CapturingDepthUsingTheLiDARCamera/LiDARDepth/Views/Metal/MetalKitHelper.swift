

import Metal
import MetalKit
import CoreVideo

class MetalKitHelper {
    private static var textureCache: CVMetalTextureCache?
    
    // Initializes the CVMetalTextureCache for the current Metal device
    private static func initializeTextureCache() {
        guard let device = MTLCreateSystemDefaultDevice(), textureCache == nil else {
            return
        }
        let status = CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        if status != kCVReturnSuccess {
            fatalError("Unable to create texture cache")
        }
    }
    
    // Ensures the texture cache is ready to be used
    private static func getTextureCache() -> CVMetalTextureCache {
        if textureCache == nil {
            initializeTextureCache()
        }
        return textureCache!
    }
    
    static func copy(texture: MTLTexture, to pixelBuffer: CVPixelBuffer, with commandBuffer: MTLCommandBuffer) {
        //print("MetalKiteHelper.copy called")
        let cache = getTextureCache()
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            print("Failed to create Metal blit encoder.")
            return
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        
        let pixelFormat = texture.pixelFormat
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, pixelFormat, width, height, 0, &cvTexture)
        
        if status == kCVReturnSuccess, let cvMetalTexture = cvTexture, let metalTexture = CVMetalTextureGetTexture(cvMetalTexture) {
            // Ensure the copy region fits within the destination texture
            //print("Created Metal Texture")
            let copyWidth = min(texture.width, metalTexture.width)
            let copyHeight = min(texture.height, metalTexture.height)
            //print("copyWidth = \(copyWidth)")
            //print("copyHeight = \(copyHeight)")
            blitEncoder.copy(from: texture,
                             sourceSlice: 0,
                             sourceLevel: 0,
                             sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                             sourceSize: MTLSize(width: copyWidth, height: copyHeight, depth: 1),
                             to: metalTexture,
                             destinationSlice: 0,
                             destinationLevel: 0,
                             destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        } else {
            print("Failed to create a Metal texture from the pixel buffer")
        }
        
        blitEncoder.endEncoding()
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        //commandBuffer.commit()
    }
}
