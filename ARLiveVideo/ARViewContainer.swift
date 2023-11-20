//
//  ARViewContainer.swift
//  ARLiveVideo
//
//  Created by HAI/T NGUYEN on 11/20/23.
//

import Foundation
import SwiftUI
import ARKit
import RealityKit
import UIKit
import MetalKit
import Metal

struct ARViewContainer: UIViewRepresentable {
    
    @Binding var percentOfRed: Int
    
    func makeUIView(context: Context) -> ARView {
        
        let arView = ARView(frame: .zero)
        arView.session.delegate = context.coordinator
        return arView
        
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        DispatchQueue.main.async {
            self.percentOfRed = context.coordinator.percentOfRed
        }
    }
    
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(percentOfRed: $percentOfRed)
        coordinator.setupMetal()
        return coordinator
    }
    
    final class Coordinator: NSObject, ARSessionDelegate {
        
        let request = VNDetectBarcodesRequest()
        
        let requestQueue = DispatchQueue(label: "Request Queue")
        
        var frameCount = 0
        @Binding var percentOfRed: Int
        
        var device: MTLDevice!
        var captureSession = AVCaptureSession()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ciContext = CIContext()
        
        var pipelineState: MTLComputePipelineState!
        var commandQueue: MTLCommandQueue!
        
        init(percentOfRed: Binding<Int>) {
            self._percentOfRed = percentOfRed
            guard let metalDevice = MTLCreateSystemDefaultDevice() else { return }
            device = metalDevice
        }
        
        var shouldRunBarcodeDetection: Bool {
            // True every ten frames.
            frameCount % 10 == 0
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            
            frameCount &+= 1
            
            // You probably don't need to run barcode detection *every* frame, that could get pretty expensive.
            if shouldRunBarcodeDetection {
                
                calculateRedRetion(in: frame)
            }
        }
        
        private func calculateRedRetion(in frame: ARFrame) {
            let pixelBuffer = frame.capturedImage
            
            let ciimage : CIImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context:CIContext = CIContext(options: nil)
            let cgImage:CGImage = context.createCGImage(ciimage, from: ciimage.extent)!
            
            analyzeRedPercentage(cgImage) { percent in
                self.percentOfRed = Int(percent)
            }
        }
        
        
        func setupMetal() {
            guard let device = device else { return }
            
            do {
                let defaultLibrary = try device.makeDefaultLibrary()
                let kernelFunction = defaultLibrary?.makeFunction(name: "analyze_red_percentage")
                pipelineState = try device.makeComputePipelineState(function: kernelFunction!)
                commandQueue = device.makeCommandQueue()
            } catch {
                fatalError("Metal setup error: \(error.localizedDescription)")
            }
        }
        
        func analyzeRedPercentage(_ image: CGImage, completion: @escaping (Double) -> Void) {
            let textureLoader = MTKTextureLoader(device: device)
            do {
                let texture = try textureLoader.newTexture(cgImage: image, options: nil)

                let commandBuffer = commandQueue.makeCommandBuffer()
                let commandEncoder = commandBuffer?.makeComputeCommandEncoder()

                guard let pipelineState = try? makePipelineState(),
                      let buffer = device.makeBuffer(length: MemoryLayout<Float>.size, options: []) else {
                    return
                }

                commandEncoder?.setComputePipelineState(pipelineState)
                commandEncoder?.setTexture(texture, index: 0)
                commandEncoder?.setBuffer(buffer, offset: 0, index: 0)

                let width = image.width
                let height = image.height
                
                print("width - height: \(width) - \(height)")
                
                let gridSize = MTLSize(width: width, height: height, depth: 1)
                let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
                commandEncoder?.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadGroupSize)

                commandEncoder?.endEncoding()
                commandBuffer?.commit()

                commandBuffer?.addCompletedHandler { _ in
                    let percentageBufferPointer = buffer.contents().bindMemory(to: Float.self, capacity: 1)
                    let percentage = percentageBufferPointer.pointee * 100.0
                    completion(Double(percentage))
                }
            } catch {
                print("Error loading texture: \(error.localizedDescription)")
            }
        }
        
        
        private func makePipelineState() throws -> MTLComputePipelineState {
            guard let library = device.makeDefaultLibrary(),
                  let function = library.makeFunction(name: "analyze_red_percentage") else {
                fatalError("Failed to create compute pipeline state")
            }
            
            return try device.makeComputePipelineState(function: function)
        }
        
        func createTexture(from image: UIImage, device: MTLDevice) -> MTLTexture? {
            guard let cgImage = image.cgImage else {
                return nil
            }

            let width = cgImage.width
            let height = cgImage.height

            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            let bitsPerComponent = 8

            guard let context = CGContext(data: nil,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: bitsPerComponent,
                                          bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return nil
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            guard let texture = device.makeTexture(descriptor: MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false)) else {
                return nil
            }

            let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                   size: MTLSize(width: width, height: height, depth: 1))

            texture.replace(region: region,
                            mipmapLevel: 0,
                            withBytes: context.data!,
                            bytesPerRow: bytesPerRow)

            return texture
        }

        func createEmptyTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture {
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )

            // Add .shaderWrite usage for the output texture
            textureDescriptor.usage = [.shaderRead, .shaderWrite]

            guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
                fatalError("Failed to create empty texture")
            }

            return texture
        }
    }
}
