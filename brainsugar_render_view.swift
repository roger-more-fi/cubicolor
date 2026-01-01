//
//  brainsugar_render_view.swift
//  created by Harri Hilding Smatt on 2025-12-28
//

import MetalKit
import SwiftUI

struct BrainsugarRenderView : UIViewRepresentable {
    var coordinator : BrainsugarRenderView.Coordinator!
    var view : MTKView = MTKView()

    init() {
        self.coordinator = BrainsugarRenderView.Coordinator(self)
    }

    func makeUIView(context: Context) -> MTKView {
        view.device = MTLCreateSystemDefaultDevice()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        return coordinator
    }

    class Coordinator : NSObject, MTKViewDelegate {
        var parent : BrainsugarRenderView
        var metalDevice : MTLDevice!
        var metalCommandQueue : MTLCommandQueue!

        var metalRenderClearPipelineState: MTLRenderPipelineState!
        var metalRenderCopyPipelineState: MTLRenderPipelineState!
        var metalRenderEnvironmentPipelineState: MTLRenderPipelineState!

        var metalBgTexture: MTLTexture!
        var metalDepthTexture: MTLTexture!
        var metalRenderTexture: MTLTexture!
        
        var metalDepthStencilState: MTLDepthStencilState!

        var rotate_x: Float = 0.0
        var rotate_y: Float = 0.0

        var tapPositions: [simd_float3] = [simd_float3](repeating: simd_float3(), count: 20)
        var tapForce: simd_float2 = simd_float2(x: 0.0, y: 0.0)

        init(_ parent : BrainsugarRenderView) {
            self.parent = parent
            
            if let metalDevice = MTLCreateSystemDefaultDevice() {
                self.metalDevice = metalDevice
            }

            self.metalCommandQueue = metalDevice.makeCommandQueue()
            let metalLibrary = metalDevice.makeDefaultLibrary()!;

            do {
                let renderClearDescriptor = MTLRenderPipelineDescriptor()
                renderClearDescriptor.vertexFunction = metalLibrary.makeFunction(name: "clear_vs")
                renderClearDescriptor.fragmentFunction = metalLibrary.makeFunction(name: "clear_fs")
                renderClearDescriptor.depthAttachmentPixelFormat = .depth32Float
                renderClearDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
                renderClearDescriptor.colorAttachments[0].isBlendingEnabled = true
                renderClearDescriptor.colorAttachments[0].alphaBlendOperation = .unspecialized
                renderClearDescriptor.colorAttachments[0].rgbBlendOperation = .add
                renderClearDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .unspecialized
                renderClearDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                renderClearDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .unspecialized
                renderClearDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                self.metalRenderClearPipelineState = try metalDevice.makeRenderPipelineState(descriptor: renderClearDescriptor)

                let renderCopyDescriptor = MTLRenderPipelineDescriptor()
                renderCopyDescriptor.vertexFunction = metalLibrary.makeFunction(name: "copy_vs")
                renderCopyDescriptor.fragmentFunction = metalLibrary.makeFunction(name: "copy_fs")
                renderCopyDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
                self.metalRenderCopyPipelineState = try metalDevice.makeRenderPipelineState(descriptor: renderCopyDescriptor)
                
                let renderEnvironmentDescriptor = MTLRenderPipelineDescriptor()
                renderEnvironmentDescriptor.vertexFunction = metalLibrary.makeFunction(name: "environment_vs")
                renderEnvironmentDescriptor.fragmentFunction = metalLibrary.makeFunction(name: "environment_fs")
                renderEnvironmentDescriptor.depthAttachmentPixelFormat = .depth32Float
                renderEnvironmentDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
                renderEnvironmentDescriptor.colorAttachments[0].isBlendingEnabled = true
                renderEnvironmentDescriptor.colorAttachments[0].alphaBlendOperation = .unspecialized
                renderEnvironmentDescriptor.colorAttachments[0].rgbBlendOperation = .add
                renderEnvironmentDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .unspecialized
                renderEnvironmentDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                renderEnvironmentDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .unspecialized
                renderEnvironmentDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                self.metalRenderEnvironmentPipelineState = try metalDevice.makeRenderPipelineState(descriptor: renderEnvironmentDescriptor)

                let metalTextureLoader = MTKTextureLoader(device: metalDevice)
                let imageBgUrl = Bundle.main.url(forResource: "brainsugar_bg", withExtension: "jpg")!
                self.metalBgTexture = try metalTextureLoader.newTexture(URL: imageBgUrl, options: nil)

                let renderDepthDescriptor = MTLTextureDescriptor()
                renderDepthDescriptor.width = 800
                renderDepthDescriptor.height = 600
                renderDepthDescriptor.depth = 1
                renderDepthDescriptor.pixelFormat = .depth32Float
                renderDepthDescriptor.usage = [.shaderRead, .renderTarget]
                renderDepthDescriptor.storageMode = .private
                renderDepthDescriptor.mipmapLevelCount = 1
                self.metalDepthTexture = metalDevice.makeTexture(descriptor: renderDepthDescriptor)

                let renderTextureDescriptor = MTLTextureDescriptor()
                renderTextureDescriptor.width = 800
                renderTextureDescriptor.height = 600
                renderTextureDescriptor.depth = 1
                renderTextureDescriptor.pixelFormat = .rgba16Float
                renderTextureDescriptor.usage = [.shaderRead, .renderTarget]
                renderTextureDescriptor.storageMode = .private
                renderTextureDescriptor.mipmapLevelCount = 1
                self.metalRenderTexture = metalDevice.makeTexture(descriptor: renderTextureDescriptor)
                
                let renderDepthStencilDescriptor = MTLDepthStencilDescriptor()
                renderDepthStencilDescriptor.depthCompareFunction = .less
                renderDepthStencilDescriptor.isDepthWriteEnabled = true
                self.metalDepthStencilState = metalDevice.makeDepthStencilState(descriptor: renderDepthStencilDescriptor)
            } catch let error {
                print(error.localizedDescription)
            }

            super.init()
        }

        func setTapPositions(_ taps: Set<UITouch>) {
            if taps.isEmpty {
                for index in 0..<20 {
                    let z = tapPositions[index].z
                    tapPositions[index].z = -abs(z)
                }
            }

            var index = 0
            taps.forEach { uiTouch in
                let pt = uiTouch.location(in: nil)
                let touchDx = pt.x - uiTouch.previousLocation(in: nil).x
                let touchDy = pt.y - uiTouch.previousLocation(in: nil).y
                tapForce = simd_float2(x: Float(touchDx), y: Float(touchDy))
                tapPositions[index] = simd_float3(Float(pt.x / 1024.0),
                                                  Float(pt.y / 1024.0),
                                                  max(tapPositions[index].z, 0.01))
                index += 1
            }
        }

        func mtkView(_ view : MTKView, drawableSizeWillChange size : CGSize) {
        }
        
        func matrix4x4_perspective_projection(inAspect: Float, inFovRAD: Float, inNear: Float, inFar: Float) -> matrix_float4x4 {
            let y = 1.0 / tan(inFovRAD * 0.5)
            let x = y / inAspect
            let z = inFar / (inFar - inNear)
            
            let X = simd_make_float4(x, 0.0, 0.0,             0.0)
            let Y = simd_make_float4(0.0, y, 0.0,             0.0)
            let Z = simd_make_float4(0.0, 0.0, z,             1.0)
            let W = simd_make_float4(0.0, 0.0, z * -inNear,   0.0)
            
            return matrix_float4x4([X, Y, Z, W])
        }
        
        func matrix4x4_look_at(pos: simd_float3, to: simd_float3, up: simd_float3) -> matrix_float4x4 {
            let z_axis = simd_normalize(to - pos)
            let x_axis = simd_normalize(simd_cross(up, z_axis))
            let y_axis = simd_cross(z_axis, x_axis)
            let t = simd_make_float3(-simd_dot(x_axis, pos), -simd_dot(y_axis, pos), -simd_dot(z_axis, pos))

            return matrix_float4x4([simd_make_float4(x_axis.x, y_axis.x, z_axis.x, 0.0),
                                    simd_make_float4(x_axis.y, y_axis.y, z_axis.y, 0.0),
                                    simd_make_float4(x_axis.z, y_axis.z, z_axis.z, 0.0),
                                    simd_make_float4(t.x,      t.y,      t.z,      1.0)])
        }

        func matrix4x4_rotate_x(_ inAngle: Float) -> matrix_float4x4 {
            let theta = inAngle * .pi / 180.0;
            let sinTheta = sin(theta);
            let cosTheta = cos(theta);
            
            return matrix_float4x4([simd_make_float4( 1.0,      0.0,       0.0, 0.0),
                                    simd_make_float4( 0.0, cosTheta, -sinTheta, 0.0),
                                    simd_make_float4( 0.0, sinTheta,  cosTheta, 0.0),
                                    simd_make_float4( 0.0,      0.0,       0.0, 1.0)])
        }

        func matrix4x4_rotate_y(_ inAngle: Float) -> matrix_float4x4 {
            let theta = inAngle * .pi / 180.0;
            let sinTheta = sin(theta);
            let cosTheta = cos(theta);
            
            return matrix_float4x4([simd_make_float4( cosTheta, 0.0, sinTheta, 0.0),
                                    simd_make_float4(      0.0, 1.0,      0.0, 0.0),
                                    simd_make_float4(-sinTheta, 0.0, cosTheta, 0.0),
                                    simd_make_float4(      0.0, 0.0,      0.0, 1.0)])
        }
        
        func matrix4x4_rotate_z(_ inAngle: Float) -> matrix_float4x4 {
            let theta = inAngle * .pi / 180.0;
            let sinTheta = sin(theta);
            let cosTheta = cos(theta);
            
            return matrix_float4x4([simd_make_float4( cosTheta,-sinTheta, 0.0, 0.0),
                                    simd_make_float4( sinTheta, cosTheta, 0.0, 0.0),
                                    simd_make_float4(      0.0,      0.0, 1.0, 0.0),
                                    simd_make_float4(      0.0,      0.0, 0.0, 1.0)])
        }

        func draw(in view : MTKView) {
            guard let drawable = view.currentDrawable else {
                return
            }
            let commandBuffer = metalCommandQueue.makeCommandBuffer()

            // render
            if true {
                rotate_x = (rotate_x + Float.random(in: 0.0...0.25) + tapForce.y * 0.001).truncatingRemainder(dividingBy: 360.0)
                rotate_y = (rotate_y + Float.random(in: 0.0...0.25) + tapForce.x * -0.001).truncatingRemainder(dividingBy: 360.0)
                
                tapForce *= 0.95
                for index in 0..<20 {
                    if tapPositions[index].z > 0.0 {
                        tapPositions[index].z = min(1.0, 1.25 * tapPositions[index].z)
                    }
                    else {
                        tapPositions[index].z *= 0.8
                    }
                }
                
                var model_m = matrix4x4_rotate_y(rotate_y) * matrix4x4_rotate_x(rotate_x)
                var view_m = matrix4x4_look_at(pos: simd_make_float3(0.0, 0.0, 4.0), to: simd_make_float3(0.0, 0.0, 0.0), up: simd_make_float3(0.0, 1.0, 0.0))
                var proj_m = matrix4x4_perspective_projection(inAspect: 2752.0 / 2064.0, inFovRAD: 55.0 * (.pi / 180.0), inNear: 1.0, inFar: 5.0)
                
                let renderClearPassDescriptor = MTLRenderPassDescriptor()
                renderClearPassDescriptor.depthAttachment.texture = metalDepthTexture
                renderClearPassDescriptor.depthAttachment.clearDepth = 1.0
                renderClearPassDescriptor.depthAttachment.loadAction = .clear
                renderClearPassDescriptor.depthAttachment.storeAction = .store
                renderClearPassDescriptor.colorAttachments[0].texture = metalRenderTexture
                renderClearPassDescriptor.colorAttachments[0].loadAction =  .load
                renderClearPassDescriptor.colorAttachments[0].storeAction = .store
                
                let renderPassDescriptor = MTLRenderPassDescriptor()
                renderPassDescriptor.depthAttachment.texture = metalDepthTexture
                renderPassDescriptor.depthAttachment.loadAction = .load
                renderPassDescriptor.depthAttachment.storeAction = .store
                renderPassDescriptor.colorAttachments[0].texture = metalRenderTexture
                renderPassDescriptor.colorAttachments[0].loadAction =  .load
                renderPassDescriptor.colorAttachments[0].storeAction = .store
                
                let renderClearCommandEncoder = commandBuffer!.makeRenderCommandEncoder(descriptor: renderClearPassDescriptor)!
                renderClearCommandEncoder.setRenderPipelineState(metalRenderClearPipelineState)
                renderClearCommandEncoder.setCullMode(.none)
                renderClearCommandEncoder.setFragmentTexture(metalBgTexture, index: 0)
                renderClearCommandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
                renderClearCommandEncoder.endEncoding()
                
                let renderEnvironmentCommandEncoder = commandBuffer!.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
                renderEnvironmentCommandEncoder.setRenderPipelineState(metalRenderEnvironmentPipelineState)
                renderEnvironmentCommandEncoder.setCullMode(.none)
                renderEnvironmentCommandEncoder.setDepthStencilState(metalDepthStencilState)
                renderEnvironmentCommandEncoder.setVertexBytes(&model_m, length: MemoryLayout<matrix_float4x4>.size, index: 0)
                renderEnvironmentCommandEncoder.setVertexBytes(&view_m, length: MemoryLayout<matrix_float4x4>.size, index: 1)
                renderEnvironmentCommandEncoder.setVertexBytes(&proj_m, length: MemoryLayout<matrix_float4x4>.size, index: 2)
                renderEnvironmentCommandEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: 4, instanceCount: 4)
                renderEnvironmentCommandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 3, instanceCount: 4)
                renderEnvironmentCommandEncoder.endEncoding()
                
                //
                // let renderParticlesCommandEncoder = commandBuffer!.makeRenderCommandEncoder(descriptor: particlesRenderPassDescriptor)
                // renderParticlesCommandEncoder!.setRenderPipelineState(metalRenderParticlesPipelineState)
                // renderParticlesCommandEncoder!.setCullMode(.none)
                // renderParticlesCommandEncoder!.setVertexBuffer(metalVarsBuffer, offset: 0, index: 0)
                // renderParticlesCommandEncoder!.setVertexBuffer(metalParticleBufferTmp, offset: 0, index: 1)
                // renderParticlesCommandEncoder!.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: renderCount)
                // renderParticlesCommandEncoder!.endEncoding()
                //
                
                let copyPassDescriptor = view.currentRenderPassDescriptor
                copyPassDescriptor!.colorAttachments[0].loadAction = .dontCare
                copyPassDescriptor!.colorAttachments[0].storeAction = .store
                
                let copyCommandEncoder = commandBuffer!.makeRenderCommandEncoder(descriptor: copyPassDescriptor!)
                copyCommandEncoder!.setRenderPipelineState(metalRenderCopyPipelineState)
                copyCommandEncoder!.setFragmentBytes(&tapPositions, length: 20 * MemoryLayout<simd_float3>.stride, index: 0)
                copyCommandEncoder!.setFragmentTexture(metalRenderTexture, index: 0)
                copyCommandEncoder!.setFragmentTexture(metalDepthTexture, index: 1)
                copyCommandEncoder!.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                copyCommandEncoder!.endEncoding()
            }

            commandBuffer!.present(drawable)
            commandBuffer!.commit()
        }
    }
}
