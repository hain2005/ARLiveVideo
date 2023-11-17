//
//  PixelProcessingShader.metal
//  ARLiveVideo
//
//  Created by HAI/T NGUYEN on 11/13/23.
//

//#include <metal_stdlib>
//using namespace metal;


// PixelProcessingShader.metal

#include <metal_stdlib>
using namespace metal;
#define THREADGROUP_SIZE 256

struct VertexOut {
    float4 position [[position]];
};

fragment float4 fragment_main(VertexOut vertex_out [[stage_in]],
                              texture2d<float, access::sample> texture [[texture(0)]],
                              sampler samplerState [[sampler(0)]]) {
    // Sample the texture at the current pixel position
    float4 inputColor = texture.sample(samplerState, vertex_out.position.xy);

    // Convert to grayscale (a simple average of RGB components)
    float gray = (inputColor.r + inputColor.g + inputColor.b) / 3.0;

    // Output the grayscale color with original alpha
    return float4(gray, gray, gray, inputColor.a);
}

kernel void redPercentageKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                                texture2d<float, access::write> outTexture [[texture(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
    // Read the input pixel
    float4 pixel = inTexture.read(gid);

    // Calculate the percentage of red intensity
    float redPercentage = pixel.r;

    // Write the red percentage to the output texture
    outTexture.write(float4(redPercentage, redPercentage, redPercentage, pixel.a), gid);
}

kernel void grayscaleKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                            texture2d<float, access::write> outTexture [[texture(1)]],
                            uint2 gid [[thread_position_in_grid]]) {
    // Read the input pixel
    float4 pixel = inTexture.read(gid);

    // Calculate the grayscale value
    float grayscale = (pixel.r + pixel.g + pixel.b) / 3.0;

    // Write the grayscale pixel to the output texture
    outTexture.write(float4(grayscale, grayscale, grayscale, pixel.a), gid);
}

//fragment float4 colorProcessingShader(VertexOut vertex [[stage_in]],
//                                      texture2d<float, access::read> colorTexture [[texture(0)]]) {
//    float4 color = colorTexture.read(vertex.position.xy);
//    return float4(color.r, 0, 0, 1);
//}


kernel void calculateRedPercentageKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                                        texture2d<float, access::write> outTexture [[texture(1)]],
                                        uint2 gid [[thread_position_in_grid]]) {
    // Read input pixel
    float4 pixel = inTexture.read(gid);

    // Calculate red intensity (adjust these coefficients based on your color detection criteria)
    float redIntensity = 0.8 * pixel.r - 0.4 * pixel.g - 0.4 * pixel.b;

    // Threshold to determine if the pixel is considered red
    float threshold = 0.5;
    float isRed = (redIntensity > threshold) ? 1.0 : 0.0;

    // Write the result to the output texture
    outTexture.write(float4(isRed, isRed, isRed, 1.0), gid);
}


kernel void analyze_red_percentage(texture2d<float, access::read> inTexture [[texture(0)]],
                                   device float* outPercentage [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {

    float redSum = 0.0;

    // Assuming RGBA format, where inTexture.read().r represents the red channel
    float4 pixel = inTexture.read(gid);
    redSum += pixel.r;
    

    //float pct = (float4(isRed, isRed, isRed, 1.0), gid);
    // Write the sum to the output buffer
    outPercentage[0] = redSum;
}
