//
//  PixelProcessingShader.metal
//  ARLiveVideo
//
//  Created by HAI/T NGUYEN on 11/13/23.
//

#include <metal_stdlib>
#include <metal_math>
using namespace metal;

//// Constants for YOLO model
//constexpr int gridSize = 13; // Grid size used by YOLO model
//constexpr int numBoundingBoxes = 5; // Number of bounding boxes predicted per grid cell
//constexpr int numClasses = 80; // Number of object classes in the model


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

kernel void outline_kernel(texture2d<float, access::read> inTexture [[texture(0)]],
                           texture2d<float, access::write> outTexture [[texture(1)]],
                           uint2 gid [[thread_position_in_grid]])
{
    // Get the pixel color from the input texture
    float4 color = inTexture.read(gid);

    // TODO: Implement your object detection algorithm here
    // For simplicity, let's assume we detect the object using a simple threshold
    float threshold = 0.5;
    if (color.r > threshold && color.g > threshold && color.b > threshold) {
        // Object detected, set outline color
        outTexture.write(float4(1.0, 0.0, 0.0, 1.0), gid);
    } else {
        // No object, set background color
        outTexture.write(float4(0.0, 0.0, 0.0, 0.0), gid);
    }
}



// Function to perform non-maximum suppression
float4 nonMaxSuppression(float4 a, float4 b, float4 c, float4 d) {
    float4 maxVals = fmax(a, fmax(b, fmax(c, d)));
    return step(maxVals, a) * a + step(maxVals, b) * b + step(maxVals, c) * c + step(maxVals, d) * d;
}

// YOLO object detection kernel
kernel void yolo_detection_kernel(texture2d<float, access::read> inTexture [[texture(0)]],
                                 texture2d<float, access::write> outTexture [[texture(1)]],
                                 constant float *modelOutputBuffer [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]])
{
    // Constants for YOLO model
    constexpr int gridSize = 13; // Grid size used by YOLO model
    constexpr int numBoundingBoxes = 5; // Number of bounding boxes predicted per grid cell
    constexpr int numClasses = 80; // Number of object classes in the model

    // Calculate the pixel coordinates in the input texture
    float2 pixelCoord = float2(gid) / float2(outTexture.get_width(), outTexture.get_height());

    // Calculate the grid cell coordinates
    int2 gridCoord = int2(pixelCoord * float2(gridSize));

    // Calculate the index of the bounding box in the model output buffer
    int bboxIndex = (gridCoord.y * gridSize + gridCoord.x) * (4 + 1 + numClasses);

    // Get bounding box parameters from the model output buffer
    float4 box = float4(modelOutputBuffer[bboxIndex],
                        modelOutputBuffer[bboxIndex + 1],
                        modelOutputBuffer[bboxIndex + 2],
                        modelOutputBuffer[bboxIndex + 3]);

    // Get confidence score
    float confidence = modelOutputBuffer[bboxIndex + 4];

    // Get class probabilities
    float4 classProbabilities = modelOutputBuffer[bboxIndex + 5];

    // Perform non-maximum suppression
    float4 result = nonMaxSuppression(box, box, box, box);

    // Draw the bounding box if the confidence score is above a threshold
    float threshold = 0.5;
    if (confidence > threshold) {
        // TODO: Draw the bounding box on the outTexture
        // You can use outTexture.write(...) to set the pixel color
        // The result variable contains the coordinates of the detected bounding box
        // You may need to convert the coordinates from grid space to pixel space
    } else {
        // No object, set background color
        outTexture.write(float4(0.0, 0.0, 0.0, 0.0), gid);
    }
}
