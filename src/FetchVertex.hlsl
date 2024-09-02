
#include "Common.hlsl"


StructuredBuffer<TriangleData> _Triangles;

void FetchVertex_float(float vertexID, 
    out float3 positionWS, 
    out float3 normalWS, 
    out float3 color,
    out float weight)
{
    TriangleData tri = _Triangles[vertexID / 3];
    VertexData input = tri.vertices[vertexID % 3];
    positionWS = input.positionWS;
    normalWS = input.normalWS;
    color = tri.color;
    weight = input.weight;
}
