#ifndef _COMMON_HLSL
#define _COMMON_HLSL

struct OriginalGrassData
{
    float3 positionWS;
};

struct GrassData
{
    int lod;
    // float3 color;
    float3 positionWS;
};

struct VertexData
{
    // uint wxyz;
    float weight;
    float3 normalWS;
    float3 positionWS;
};

struct TriangleData
{
    float3 color; 
    VertexData vertices[3];
};

// struct DispatchArgs
// {
//     uint x, y, z;
//     uint maxCount;
// };

struct IndirectArgs
{
    uint numVerticesPerInstance;        // N * 3
    uint numInstances;                  // 1
    uint startVertexIndex;              // 0
    uint startInstanceIndex;            // 0
    uint startLocation;                 // 0
};

#endif