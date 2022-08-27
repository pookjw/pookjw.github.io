//
//  Renderer.swift
//  Pipeline
//
//  Created by Jinwoo Kim on 8/28/22.
//

import MetalKit

class Renderer: NSObject {
    static var device: MTLDevice!
    static var commandQueue: MTLCommandQueue!
    static var library: MTLLibrary!
    var mesh: MTKMesh!
    var vertexBuffer: MTLBuffer!
    var pipelineState: MTLRenderPipelineState!
    
    init(metalView: MTKView) {
        let device: MTLDevice = MTLCreateSystemDefaultDevice()!
        let commandQueue: MTLCommandQueue = device.makeCommandQueue()!
        
        Self.device = device
        Self.commandQueue = commandQueue
        
        metalView.device = device
        metalView.clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0)
        
        super.init()
        
        metalView.delegate = self
        
        // create the mesh
        let allocator: MTKMeshBufferAllocator = .init(device: device)
        let size: Float = 0.8
        let mdlMesh: MDLMesh = .init(boxWithExtent: [size, size, size],
                                     segments: [1, 1, 1],
                                     inwardNormals: false,
                                     geometryType: .triangles,
                                     allocator: allocator)
        
        self.mesh = try! .init(mesh: mdlMesh, device: device)
        vertexBuffer = self.mesh.vertexBuffers[0].buffer
        
        // create the shader function library
        let library: MTLLibrary = device.makeDefaultLibrary()!
        Self.library = library
        let vertexFunction: MTLFunction = library.makeFunction(name: "vertex_main")!
        let fragmentFunction: MTLFunction = library.makeFunction(name: "fragment_main")!
        
        // create the pipeline state object
        let pipelineDescriptor: MTLRenderPipelineDescriptor = .init()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mdlMesh.vertexDescriptor)
        
        self.pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
        let commandBuffer: MTLCommandBuffer = Self.commandQueue.makeCommandBuffer()!
        let descriptor: MTLRenderPassDescriptor = view.currentRenderPassDescriptor!
        let renderEncoder: MTLRenderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        mesh.submeshes.forEach { submesh in
            renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
        }
        
        renderEncoder.endEncoding()
        let drawable: CAMetalDrawable = view.currentDrawable!
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
