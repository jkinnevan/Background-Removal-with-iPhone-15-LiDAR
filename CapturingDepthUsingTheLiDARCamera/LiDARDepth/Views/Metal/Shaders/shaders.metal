/*
 COM S 575 (Spring 2024 - Iowa State University)
 Project by Jessica Kinnevan, Toral Chauhan, Naifa Alqahtani
 
 This shader file was orginally a part of a sample code project provided by Apple called "Capturing depth using the LiDAR camera"
 Available here:
 https://developer.apple.com/documentation/avfoundation/additional_data_capture/capturing_depth_using_the_lidar_camera
 
 Most of the original code was removed. Any remaning original code is indicated below.
*/

#include <metal_stdlib>

using namespace metal;

// Begin original example code //

typedef struct
{
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
} ColorInOut;


// Display a 2D texture
vertex ColorInOut planeVertexShader(Vertex in [[stage_in]])
{
    ColorInOut out;
    out.position = float4(in.position, 0.0f, 1.0f);
    out.texCoord = in.texCoord;
    return out;
}

// Shade a 2D plane by passing through the texture input (Provided by Apple Example)
fragment float4 planeFragmentShader(ColorInOut in [[stage_in]], texture2d<float, access::sample> textureIn [[ texture(0) ]])
{
    // define a sampler object - magnification/minificiation filter set to linear filtering
    constexpr sampler colorSampler(address::clamp_to_edge, filter::linear);
    float4 sample = textureIn.sample(colorSampler, in.texCoord);
    return sample;
}

// End original example code //


// Begin code created by Team 7 - Jessica Kinnevan, Toral Chauhan, Naifa Alqahtani

// 3x3 kernel
constant float2 kernelOffsets3[9] = {
    float2(-1, 1), float2(0, 1), float2(1, 1),   // top row (above current pixel)
    float2(-1, 0), float2(0, 0), float2(1, 0),   // middle row (current pixel row)
    float2(-1, -1), float2(0, -1), float2(1, -1) // bottom row (below current pixel)
};

// Dilate first and immediately use the result for erosion
half dilateAndErode3(texture2d<half> tex, float2 coord, sampler s, float texelWidth) {
    half maxAlpha = 0.0h;
    half minAlpha = 1.0h;
        
    for (int i = 0; i < 9; ++i) {
        float2 offset = kernelOffsets3[i] * float2(texelWidth, texelWidth);
        half dilatedSampleAlpha = tex.sample(s, coord + offset).a;
        maxAlpha = max(maxAlpha, dilatedSampleAlpha);
    }

    for (int i = 0; i < 9; ++i) {
        float2 offset = kernelOffsets3[i] * float2(texelWidth, texelWidth);
        half erodedSampleAlpha = tex.sample(s, coord + offset).a;
        minAlpha = min(minAlpha, erodedSampleAlpha);
    }
    if (maxAlpha > 1){
        maxAlpha = 0;
    }

    return minAlpha; // return the eroded alpha after dilation
}


// 5x5 kernel
constant float2 kernelOffsets5[25] = {
    float2(-2, -2), float2(-1, -2), float2(0, -2), float2(1, -2), float2(2, -2),
    float2(-2, -1), float2(-1, -1), float2(0, -1), float2(1, -1), float2(2, -1),
    float2(-2,  0), float2(-1,  0), float2(0,  0), float2(1,  0), float2(2,  0),
    float2(-2,  1), float2(-1,  1), float2(0,  1), float2(1,  1), float2(2,  1),
    float2(-2,  2), float2(-1,  2), float2(0,  2), float2(1,  2), float2(2,  2)
};

//Dilate first and immediately use the result for erosion
half dilateAndErode5(texture2d<half> tex, float2 coord, sampler s, float texelWidth) {
    half maxAlpha = 0.0h;
    half minAlpha = 1.0h;

    // Dilation
    for (int i = 0; i < 25; ++i) {
        float2 offset = kernelOffsets5[i] * float2(texelWidth, texelWidth);
        half dilatedSampleAlpha = tex.sample(s, coord + offset).a;
        maxAlpha = max(maxAlpha, dilatedSampleAlpha);
    }

    // Erosion
    for (int i = 0; i < 25; ++i) {
        float2 offset = kernelOffsets5[i] * float2(texelWidth, texelWidth);
        half erodedSampleAlpha = tex.sample(s, coord + offset).a;
        minAlpha = min(minAlpha, erodedSampleAlpha);
    }

    return minAlpha; // return the eroded alpha after dilation
}


// 7x7 kernel
constant float2 kernelOffsets7[49] = {
    float2(-3, -3), float2(-2, -3), float2(-1, -3), float2(0, -3), float2(1, -3), float2(2, -3), float2(3, -3),
    float2(-3, -2), float2(-2, -2), float2(-1, -2), float2(0, -2), float2(1, -2), float2(2, -2), float2(3, -2),
    float2(-3, -1), float2(-2, -1), float2(-1, -1), float2(0, -1), float2(1, -1), float2(2, -1), float2(3, -1),
    float2(-3,  0), float2(-2,  0), float2(-1,  0), float2(0,  0), float2(1,  0), float2(2,  0), float2(3,  0),
    float2(-3,  1), float2(-2,  1), float2(-1,  1), float2(0,  1), float2(1,  1), float2(2,  1), float2(3,  1),
    float2(-3,  2), float2(-2,  2), float2(-1,  2), float2(0,  2), float2(1,  2), float2(2,  2), float2(3,  2),
    float2(-3,  3), float2(-2,  3), float2(-1,  3), float2(0,  3), float2(1,  3), float2(2,  3), float2(3,  3)
};

// Dilate first and immediately use the result for erosion
half dilateAndErode7(texture2d<half> tex, float2 coord, sampler s, float texelWidth) {
    half maxAlpha = 0.0h;
    half minAlpha = 1.0h;

    // Dilation
    for (int i = 0; i < 49; ++i) {  // Adjusted loop counter to 49 for the 7x7 kernel
        float2 offset = kernelOffsets7[i] * float2(texelWidth, texelWidth);
        half dilatedSampleAlpha = tex.sample(s, coord + offset).a;
        maxAlpha = max(maxAlpha, dilatedSampleAlpha);
    }

    // Erosion
    for (int i = 0; i < 49; ++i) {  // Adjusted loop counter to 49 for the 7x7 kernel
        float2 offset = kernelOffsets7[i] * float2(texelWidth, texelWidth);
        half erodedSampleAlpha = tex.sample(s, coord + offset).a;
        minAlpha = min(minAlpha, erodedSampleAlpha);
    }

    return minAlpha; // Return the eroded alpha after dilation
}

//9x9 kernel
constant float2 kernelOffsets9[81] = {
    float2(-4, 4), float2(-3, 4), float2(-2, 4), float2(-1, 4), float2(0, 4), float2(1, 4), float2(2, 4), float2(3, 4), float2(4, 4),
    float2(-4, 3), float2(-3, 3), float2(-2, 3), float2(-1, 3), float2(0, 3), float2(1, 3), float2(2, 3), float2(3, 3), float2(4, 3),
    float2(-4, 2), float2(-3, 2), float2(-2, 2), float2(-1, 2), float2(0, 2), float2(1, 2), float2(2, 2), float2(3, 2), float2(4, 2),
    float2(-4, 1), float2(-3, 1), float2(-2, 1), float2(-1, 1), float2(0, 1), float2(1, 1), float2(2, 1), float2(3, 1), float2(4, 1),
    float2(-4, 0), float2(-3, 0), float2(-2, 0), float2(-1, 0), float2(0, 0), float2(1, 0), float2(2, 0), float2(3, 0), float2(4, 0),
    float2(-4,-1), float2(-3,-1), float2(-2,-1), float2(-1,-1), float2(0,-1), float2(1,-1), float2(2,-1), float2(3,-1), float2(4,-1),
    float2(-4,-2), float2(-3,-2), float2(-2,-2), float2(-1,-2), float2(0,-2), float2(1,-2), float2(2,-2), float2(3,-2), float2(4,-2),
    float2(-4,-3), float2(-3,-3), float2(-2,-3), float2(-1,-3), float2(0,-3), float2(1,-3), float2(2,-3), float2(3,-3), float2(4,-3),
    float2(-4,-4), float2(-3,-4), float2(-2,-4), float2(-1,-4), float2(0,-4), float2(1,-4), float2(2,-4), float2(3,-4), float2(4,-4)
};

// Dilate first and immediately use the result for erosion
half dilateAndErode9(texture2d<half> tex, float2 coord, sampler s, float texelWidth) {
    half maxAlpha = 0.0h;
    half minAlpha = 1.0h;

    // Perform dilation
    for (int i = 0; i < 81; ++i) {
        float2 offset = kernelOffsets9[i] * float2(texelWidth, texelWidth);
        half sampleAlpha = tex.sample(s, coord + offset).a;
        maxAlpha = max(maxAlpha, sampleAlpha);
    }

    // Perform erosion
    for (int i = 0; i < 81; ++i) {
        float2 offset = kernelOffsets9[i] * float2(texelWidth, texelWidth);
        half sampleAlpha = tex.sample(s, coord + offset).a;
        minAlpha = min(minAlpha, sampleAlpha);
    }

    return minAlpha; // return the eroded alpha after dilation
}


/* Shader 1 written by Team 7 - Jessica Kinnevan, Toral Chauhan, Naifa Alqahtani
   planeFragmentShaderRemoveBackground sets the alpha of the foreground camera image
   based on the depthAdjustment (depth threshold) and the rollOff value.
*/
fragment half4 planeFragmentShaderRemoveBackground(
    ColorInOut in [[stage_in]],
    texture2d<half> colorYTexture [[ texture(0) ]],
    texture2d<half> colorCbCrTexture [[ texture(1) ]],
    texture2d<float> depthTexture [[ texture(2) ]],
    constant float& exposureAdjustment [[buffer(0)]],
    constant float& depthAdjustment [[buffer(1)]],
    constant float& redAdjustment [[buffer(2)]],
    constant float& greenAdjustment [[buffer(3)]],
    constant float& blueAdjustment [[buffer(4)]],
    constant bool& isBackgroundCntlOn [[buffer(5)]],
    constant float& rollOff [[buffer(6)]])
{
    
    // define a sampler object - magnification/minificiation filter set to linear filtering
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);

    // Sample the depth texture to get the depth value (32-bit float) for the current texel
    float depth = depthTexture.sample(textureSampler, in.texCoord).r;
    
    // Sample Y and CbCr textures provided by camera capture data
    // luminance is on the first channel (.r) and put into 16-bit float y
    half y = colorYTexture.sample(textureSampler, in.texCoord).r;
    // chrominance is on the first two channels (.rg) and put into 16-bit float vecotr uv (uv.x and uv.y)
    half2 uv = colorCbCrTexture.sample(textureSampler, in.texCoord).rg - half2(0.5, 0.5);
   
    // Compute RGBA values based on YUV to RGBA conversion formula (provided by Apple example code)
    // rgbaResult consists of 4 float channels (.r, .g, .b, .a)
    half4 rgbaResult = half4(y + 1.402 * uv.y, y - 0.7141 * uv.y - 0.3441 * uv.x, y + 1.772 * uv.x, 1.0);
    
    float range = rollOff; // Define the depth range for smoothing edges
    float smoothStep = smoothstep(depthAdjustment, depthAdjustment + range, depth); // Compute smoothed step transition
    
    // If background toggle is off adjust color on high color depth image text before compression for second shader
    if (!isBackgroundCntlOn) {                  // FOREGROUND IMAGE
        rgbaResult.rgb *= exposureAdjustment;   // Apply exposure adjustment
        rgbaResult.r *= redAdjustment;          // Apply red channel saturation adjustment
        rgbaResult.g *= greenAdjustment;        // Apply green channel saturation adjustment
        rgbaResult.b *= blueAdjustment;         // Apply blue channel saturation adjustment
    }

    // Set the alpha for the current texel based on the smoothStep value
    rgbaResult.a = 1-smoothStep;
    
    return rgbaResult;
}

/* Shader 2 written by Team 7 - Jessica Kinnevan, Toral Chauhan, Naifa Alqahtani
   planeFragmentShaderConvolution attempts to smooth the jagged transparency
   edges of the foreground image that are a result of the lower resolution
   lidar depth texture.  The shader performs a morphogological close using
   a dilation followed by and erosion for kernels of the following sizes:
   none, 3x3, 5x5, 7x7, and 9x9, which are selected by edgeSlide. edgeSlide
   is a float instead of an integer because it was connected to a slider,
   which does not support integer data types. The kernel value is based
   on the range of the edgeSlide variable. For example if edgeSlide is between
   3 and 5 (not including 5), the kernel selected is 3x3. The kernels and
   convolution functions are defined above. This shader also places a background
   image under the foreground image and adjusts the color channels and exposure
   of the background image based on the corresponding variables which are
   connected to sliders on the user interface. The background toggle has to be
   on to enable these adjustments, otherwise the sliders adjust the foreground
   image in the planeFragmentShaderRemoveBackground shader.
*/
fragment half4 planeFragmentShaderConvolution(
    ColorInOut in [[stage_in]],
    texture2d<half, access::sample> intermediateTexture [[ texture(0) ]],
    texture2d<half> backgroundTexture [[ texture(1) ]],
    constant float& exposureAdjustment [[buffer(0)]],
    constant float& redAdjustment [[buffer(1)]],
    constant float& greenAdjustment [[buffer(2)]],
    constant float& blueAdjustment [[buffer(3)]],
    constant bool& isBackgroundCntlOn [[buffer(4)]],
    constant float& edgeSlide [[buffer(5)]])
{
    // define a sampler object - magnification/minificiation filter set to linear filtering
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    
    // Sample the texture at the coordinates provided by the vertex shader
    // This RGBA has a lower color depth than in the first shader, havinf been
    // rendered to a .bgra8Unorm then put back into a 16-bit float texture so
    // the color adjustments are done in the first shader instead of here.
    // rgbaResult consists of 4 float channels (.r, .g, .b, .a)
    half4 rgbaResult = intermediateTexture.sample(textureSampler, in.texCoord);
    
    // Calculate texel width based on texture size (1290 x 1720 pixels)
    float texelWidth = 1.0 / float(intermediateTexture.get_width());
   
    // Get current current texel RGBA data for background image
    float2 coord = in.texCoord;
    half4 background = backgroundTexture.sample(textureSampler, coord);

    // If background toggle is on
    if (isBackgroundCntlOn) {                   // BACKGROUND IMAGE
        background.rgb *= exposureAdjustment;   // Apply exposure adjustment
        background.r *= redAdjustment;          // Apply red channel gain adjustment
        background.g *= greenAdjustment;        // Apply green channel gain adjustment
        background.b *= blueAdjustment;         // Apply blue channel gain adjustment
    }
    
    // Select kernel size based on edgeSlide ranges
    if (edgeSlide >= 3 && edgeSlide < 5){
        // Apply dilation and erosion combined
        rgbaResult.a = dilateAndErode3(intermediateTexture, in.texCoord, textureSampler, texelWidth);
    }
    else{
        if (edgeSlide >= 5 && edgeSlide < 7){
            // Apply dilation and erosion combined
            rgbaResult.a = dilateAndErode5(intermediateTexture, in.texCoord, textureSampler, texelWidth);
        }
        else{
            if (edgeSlide >= 7 && edgeSlide < 9){
                // Apply dilation and erosion combined
                rgbaResult.a = dilateAndErode7(intermediateTexture, in.texCoord, textureSampler, texelWidth);
            }
            else{
                if (edgeSlide >= 9){
                    // Apply dilation and erosion combined
                    rgbaResult.a = dilateAndErode9(intermediateTexture, in.texCoord, textureSampler, texelWidth);
                }
            }
        }
    }
    
    // blend the foreground image with the background image using the alpha of each texel.
    rgbaResult = mix(background, rgbaResult, rgbaResult.a);
    
    return rgbaResult;
    
}
