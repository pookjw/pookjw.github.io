# Metal by Tutorials

[Metal by Tutorials (raywenderlich.com)](https://www.raywenderlich.com/books/metal-by-tutorials) 책을 정리한 글입니다.


- [Chapter 1: Hello, Metal!](#chapter-1)

# <a name="chapter-1">Chapeter 1: Hello, Metal!</a>


Metal을 사용할 때는 'Metal 초기 설정 (Initialize Metal)' -> 'Model을 불러 옴 (Load a model)' -> 'Set up the pipeline (pipeline 설정)' -> 'Render' 과정을 거치게 된다.

queue, buffer, encoder, pipeline이라는 개념이 등장한다. queue, pipeline는 한 번만 생성되며 이 queue를 통해 매 frame마다 command를 처리한다. 각 command들을 buffer라고 부르며 매 frame마다 새로 생성된다, buffer는 encoder를 포함한다. encoder는 매 frame마다 pipeline을 통해 GPU에 연산할 값을 전송하고 받아 오며 draw를 담당한다.

![](1.png)

![](2.png)

## Practice

![](3.png)

```swift
import UIKit
import MetalKit

class ViewController: UIViewController {
    private var commandQueue: MTLCommandQueue!
    private var mtkMesh: MTKMesh!
    private var pipelineState: MTLRenderPipelineState!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let device: MTLDevice = MTLCreateSystemDefaultDevice()!
        print(device.name) // 'Apple iOS simulator GPU' or 'Apple M1 Ultra'
        
        let frame: CGRect = .init(x: .zero, y: .zero, width: 600.0, height: 600.0)
        let mtkView: MTKView = .init(frame: frame, device: device)
        mtkView.clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0)
        mtkView.delegate = self
        
        view.addSubview(mtkView)
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mtkView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mtkView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            mtkView.widthAnchor.constraint(equalToConstant: frame.width),
            mtkView.heightAnchor.constraint(equalToConstant: frame.height)
        ])
        
        //
        
        // mesh data를 관리할 메모리를 할당해주는 객체
        let allocator: MTKMeshBufferAllocator = .init(device: device)
        
        // 구(sphere) 생성
        // extent: 비율
        // segments: 구의 각의 개수 (숫자가 클 수록 더 완벽한 원에 가까워 질 것)
        // inwardNormals: https://mathinsight.org/applet/sphere_inward_normal_vector - 뭔 차이지???
        // geometryType: mesh를 그리는 방식 - 삼각형 방식으로 mesh를 그림
        let mdlMesh: MDLMesh = .init(sphereWithExtent: [0.75, 0.75, 0.75],
                                     segments: [100, 100],
                                     inwardNormals: false,
                                     geometryType: .triangles,
                                     allocator: allocator)
        
        // MetalKit에서 쓸 수 있는 Mesh 생성
        let mtkMesh: MTKMesh = try! .init(mesh: mdlMesh, device: device)
        self.mtkMesh = mtkMesh
        
        // queue 생성
        let commandQueue: MTLCommandQueue = device.makeCommandQueue()!
        self.commandQueue = commandQueue
        
        // Library 정의
        let shader: String = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexIn {
            float4 position [[attribute(0)]];
        };
        
        vertex float4 vertex_main(const VertexIn vertex_in [[stage_in]])
        {
            return vertex_in.position;
        }
        
        fragment float4 fragment_main() {
            return float4(1, 0, 0, 1);
        }
        """
        
        let library: MTLLibrary = try! device.makeLibrary(source: shader, options: nil)
        let vertexFunction: MTLFunction = library.makeFunction(name: "vertex_main")!
        let fragmentFunction: MTLFunction = library.makeFunction(name: "fragment_main")!
        
        // Pipline 설정
        let pipelineDescriptor: MTLRenderPipelineDescriptor = .init()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mtkMesh.vertexDescriptor)
        
        let pipelineState: MTLRenderPipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        self.pipelineState = pipelineState
    }
}

extension ViewController: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    
    func draw(in view: MTKView) {
        // command buffer 생성
        let commandBuffer: MTLCommandBuffer = commandQueue.makeCommandBuffer()!
        
        // View의 Render Pass Descriptor를 생성한다. 이 descriptor는 render를 어디로 해야 할지 (attachments)를 담고 있다.
        let renderPassDescriptor: MTLRenderPassDescriptor = view.currentRenderPassDescriptor!
        
        // encoder 생성
        let renderEncoder: MTLRenderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(mtkMesh.vertexBuffers[0].buffer, offset: 0, index: 0)
        
        let submesh: MTKSubmesh = mtkMesh.submeshes.first!
        
        renderEncoder.drawIndexedPrimitives(type: .line,
                                            indexCount: submesh.indexCount,
                                            indexType: submesh.indexType,
                                            indexBuffer: submesh.indexBuffer.buffer,
                                            indexBufferOffset: 0)
        
        renderEncoder.endEncoding()
        
        let drawable: CAMetalDrawable = view.currentDrawable!
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
```
