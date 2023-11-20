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

kernel void analyze_red_percentage(texture2d<float, access::read> inTexture [[texture(0)]],
                                   device float* outPercentage [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {

    float redSum = 0.0;

    // Assuming RGBA format, where inTexture.read().r represents the red channel
    float4 pixel = inTexture.read(gid);
    redSum += pixel.r;
    
    // Write the sum to the output buffer
    outPercentage[0] = redSum;
}
