//
//  ContentView.swift
//  ARLiveVideo
//
//  Created by HAI/T NGUYEN on 11/13/23.
//

import SwiftUI
import ARKit
import RealityKit
import UIKit
import MetalKit
import Metal
class AudioManager : ObservableObject {
    var audioPlayer : AVAudioPlayer?
    
     
    
    func loadAudio(filename: String) {
        
        guard let audioData = NSDataAsset(name: filename)?.data else {
            return
        }
        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.numberOfLoops = -1
            
        } catch {
            print("[shark], audioPlayer cannot load",error)
        }
    }
    
    func playAudio() {
        audioPlayer?.play()
    }
    
    func pauseAudio() {
        audioPlayer?.pause()
    }
}

struct ContentView : View {
    @State private var percentOfRed = 0
    
    var player1 = AVAudioPlayer()
    @ObservedObject var audioManager = AudioManager()
    @State var audioPlayer: AVAudioPlayer?
    
    init() {
        audioManager.loadAudio(filename: "alert")
    }
    
    var body: some View {
        ZStack {
            ARViewContainer(percentOfRed: $percentOfRed)
            VStack {
                Spacer()
                Text("% of red \(percentOfRed)")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
                    .padding(.bottom, 40)
                    .onChange(of: percentOfRed) { selection in
                        
                         if (percentOfRed > 50) {
                            //print("play")
                            audioManager.playAudio()
                        } else {
                            //print("pause")
                            audioManager.pauseAudio()
                        }
                    }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

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
            let image:UIImage = UIImage(cgImage: cgImage)

//            convertImageToRedArrayAsync(image: image) { percent in
//                self.percentOfRed = Int(percent ?? 0)
//                print("red %: \(String(describing: self.percentOfRed))")
//            }
            
            analyzeRedPercentage(cgImage) { percent in
                self.percentOfRed = Int(percent ?? 0)
                //print("red %: \(String(describing: self.percentOfRed))")

            }
        }
        
        private func detectBarcodes(in frame: ARFrame) {
            // Perform the request off the main queue to avoid blocking the UI (and the ARSessionDelegate, who's methods are by default called on the main queue).
            requestQueue.async { [unowned self] in
                let requestHandler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage)
                
                do {
                    try requestHandler.perform([request])
                    
                    if let results = request.results {
                        for result in results {
                            print(result)
                        }
                    }
                } catch {
                    fatalError(error.localizedDescription)
                }
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
        
        func convertImageToRedArrayAsync(image: UIImage, completion: @escaping (Double?) -> Void) {
            DispatchQueue.global(qos: .background).async {
                //let percentRed = self.calculateRedPercentageUsingMetal(image: image)
                let percentRed = Double(self.calculateRedPercentage(from: image))
                DispatchQueue.main.async {
                    completion(percentRed)
                }
            }
        }
        
        private func calculateRedPercentage1(image: UIImage) -> Double {
            guard let ciImage = CIImage(image: image) else {
                print("error image")
                return 0.0
            }

            let redMask = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            let filteredImage = ciImage.applyingFilter("CIColorMask", parameters: ["inputMaskImage": redMask])

            let area = ciImage.extent.size.width * ciImage.extent.size.height
            let redArea = filteredImage.extent.size.width * filteredImage.extent.size.height

            let redPercentage = (redArea / area) * 100.0
            print("% \(redPercentage)")
            return Double(redPercentage)
        }
        
        func convertImageToRedArray(image: UIImage) -> Double? {
            //let thresholdValue: UInt8 = 100
            guard let cgImage = image.cgImage else {
                return nil
            }
            
            
            let width = cgImage.width
            let height = cgImage.height

            guard let dataProvider = cgImage.dataProvider,
                  let data = dataProvider.data,
                  let pointer = CFDataGetBytePtr(data) else {
                print("error")
                return nil
            }

            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width

            //var percent: Double = 0
            var hitCount = 0.0
            let totalPizel = Double(width * height)
            for y in 0..<height {
                for x in 0..<width {
                    let pixelOffset = (y * bytesPerRow) + (x * bytesPerPixel)
                    let red = UInt8(pointer[pixelOffset])
                    let green = UInt8(pointer[pixelOffset + 1])
                    let blue = UInt8(pointer[pixelOffset + 2])

                    if (green < 20 || blue < 20) && red > 50 {
                    //if red > 100 {
                        //print("red : \(red)")
                        hitCount += 1
                    }
                    
                    //rgbArray[y][x] = (red, green, blue)
                }
            }
            //print(rgbArray.count)
            print("hit - total : \(hitCount) - \(totalPizel)")
            return Double((hitCount / totalPizel) * 100)
        }
        

        func calculateRedPercentage(image: UIImage) -> Double {
            guard let ciImage = CIImage(image: image) else {
                fatalError("Unable to create CIImage from UIImage")
            }

            let extent = ciImage.extent
            let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(extent.width * extent.height * 4))

            let context = CIContext()
            context.render(ciImage, toBitmap: pixels, rowBytes: Int(extent.width) * 4, bounds: extent, format: CIFormat.RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

            var redPixelCount = 0

            for y in 0..<Int(extent.height) {
                for x in 0..<Int(extent.width) {
                    let index = (y * Int(extent.width) + x) * 4
                    let red = pixels[index]
                    let green = pixels[index + 1]
                    let blue = pixels[index + 2]

                    if red > 50 && green < 20 && blue < 20 {
                        // Adjust the threshold values based on your specific requirements
                        redPixelCount += 1
                    }
                }
            }

            let totalPixels = Int(extent.width) * Int(extent.height)
            let redPercentage = Double(redPixelCount) / Double(totalPixels) * 100.0

            pixels.deallocate()
            print("hit - total : \(redPixelCount) - \(totalPixels)")
            return redPercentage
        }


        func calculateRedPercentageUsingMetal(image: UIImage) -> Double {
            guard let device = MTLCreateSystemDefaultDevice() else {
                fatalError("Metal is not supported on this device")
            }

            guard let ciImage = CIImage(image: image) else {
                fatalError("Unable to create CIImage from UIImage")
            }

            let metalContext = CIContext(mtlDevice: device)

            let extent = ciImage.extent
            let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(extent.width * extent.height * 4))

            metalContext.render(ciImage, toBitmap: pixels, rowBytes: Int(extent.width) * 4, bounds: extent, format: CIFormat.RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

            var redPixelCount = 0

            let bufferSize = Int(extent.width) * Int(extent.height) * 4
            let buffer = device.makeBuffer(bytes: pixels, length: bufferSize, options: [])

            if let contents = buffer?.contents() {
                let pointer = contents.bindMemory(to: UInt8.self, capacity: bufferSize)
                for i in stride(from: 0, to: bufferSize, by: 4) {
                    let red = Int(pointer[i])
                    let green = Int(pointer[i + 1])
                    let blue = Int(pointer[i + 2])

                    //let rgb = (red, green, blue)
                    //print("rgb: \(rgb)")  (155, 100, 100)
                    //if redShades.contains(where: { $0 == rgb }) {
                    if red > 20 && green < 40 && blue < 40 {
                        // Adjust the threshold values based on your specific requirements
                        redPixelCount += 1
                    }

                }
            }

            let totalPixels = Int(extent.width) * Int(extent.height)
            let redPercentage = Double(redPixelCount) / Double(totalPixels) * 100.0

            //print("hit - total : \(redPixelCount) - \(totalPixels)")
            pixels.deallocate()

            return redPercentage
        }

        func processImageWithMetal(image: MTLTexture, output: MTLTexture, pipelineState: MTLComputePipelineState, commandQueue: MTLCommandQueue) {
            // Create a command buffer
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }

            // Create a compute command encoder
            guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                return
            }

            // Set the compute pipeline state
            computeEncoder.setComputePipelineState(pipelineState)

            // Set the input and output textures
            computeEncoder.setTexture(image, index: 0)
            computeEncoder.setTexture(output, index: 1)

            // Calculate thread group and grid sizes
            let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroupsPerGrid = MTLSize(
                width: (image.width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                height: (image.height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
                depth: 1
            )

            // Set up any additional parameters for your kernel function here

            // Dispatch the compute kernel
            computeEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

            // End the encoding
            computeEncoder.endEncoding()

            // Commit the command buffer
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        func calculateRedPercentage(from image: UIImage) -> Float {
            guard let device = self.device else {
                print("calculateRedPercentage device error")
                return 0.0
            }            
            guard let commandQueue = commandQueue else {
                             print("calculateRedPercentage commandQueue error")
                             return 0.0
                         }            
            guard let buffer = commandQueue.makeCommandBuffer() else {
                print("calculateRedPercentage buffer error")
                return 0.0
            }
            guard let texture = createTexture(from: image, device: device) else {
                print("calculateRedPercentage texture error")
                return 0.0
            }
            
            let inputTexture = texture,
                outputTexture = createEmptyTexture(device: device, width: inputTexture.width, height: inputTexture.height)

            let computeCommandEncoder = buffer.makeComputeCommandEncoder()
            computeCommandEncoder?.setComputePipelineState(pipelineState)
            computeCommandEncoder?.setTexture(inputTexture, index: 0)
            computeCommandEncoder?.setTexture(outputTexture, index: 1)

            let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
            let numThreadgroups = MTLSize(width: (inputTexture.width + threadsPerGroup.width - 1) / threadsPerGroup.width,
                                          height: (inputTexture.height + threadsPerGroup.height - 1) / threadsPerGroup.height,
                                          depth: 1)
            computeCommandEncoder?.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)

            computeCommandEncoder?.endEncoding()
            buffer.commit()
            buffer.waitUntilCompleted()

            let outputPixels = UnsafeMutablePointer<Float>.allocate(capacity: outputTexture.width * outputTexture.height * 4)
            outputTexture.getBytes(outputPixels,
                                   bytesPerRow: outputTexture.width * 4 * MemoryLayout<Float>.size,
                                   from: MTLRegionMake2D(0, 0, outputTexture.width, outputTexture.height),
                                   mipmapLevel: 0)

            let outputPixelArray = Array(UnsafeBufferPointer(start: outputPixels, count: outputTexture.width * outputTexture.height * 4))
            
            let redPixelCount = outputPixelArray.reduce(0, { $0 + ($1 > 0.5 ? 1 : 0) })
            //let redPixelCount = outputPixels.reduce(0, { $0 + ($1 > 0.5 ? 1 : 0) })
            let totalPixelCount = outputTexture.width * outputTexture.height
            let redPercentage = Float(redPixelCount) / Float(totalPixelCount) * 100.0

            free(outputPixels)

            print("calculateRedPercentage: \(redPercentage)")
            return redPercentage
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

                let gridSize = MTLSize(width: 8, height: 8, depth: 1)
                let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
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

#Preview {
    ContentView()
}
