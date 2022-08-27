//
//  Shaders.metal
//  Pipeline
//
//  Created by Jinwoo Kim on 8/28/22.
//

#include <metal_stdlib>
using namespace metal;

// vertex descriptor와 대응하는 데이터
/*
 let vertexDescriptor: MTLVertexDescriptor = .init()
 vertexDescriptor.attributes[0].format = .float3
 vertexDescriptor.attributes[0].offset = 0
 vertexDescriptor.attributes[0].bufferIndex = 0
 */
struct VertexIn {
    float4 position [[attribute(0)]];
};

vertex float4 vertex_main(const VertexIn vertexIn [[stage_in]]) {
    float4 position = vertexIn.position;
    position.y -= 0.3;
    return position;
}

fragment float4 fragment_main() {
    return float4(0, 0, 1, 1);
}
