#ifndef _GRASS_COMMON_HLSL
#define _GRASS_COMMON_HLSL

#include "Common.hlsl"
#include "Math.hlsl"

#define _CURVATION_LO   (PI * 0.1)
#define _CURVATION_HI   (PI * 0.8)
#define _DIST_RANGE     0.125
#define _BASE_P         0.0125      // base penetration
#define _BASE_H         0.0250      // base height
#define _HEIGHT         0.8000      // height
#define _WIDTH          0.0500
#define _OFFSET         -0.0125

#define LOD_MIN_DISTANCE 5.0
#define LOD_MAX_DISTANCE 100.0
// #define LOD_LEVELS 4.0   // 0 1 2 3, the higher value, the better quality
#define LOD_LEVELS 5.0
#define LOD_MAX 4
#define LOD_MIN 0

float _Time;
float3 _Wind;

AppendStructuredBuffer<TriangleData> _Triangles;
RWStructuredBuffer<IndirectArgs> _IndirectArgsBuffer;

float3 _WorldSpaceCameraPos;
float4x4 _ViewProj;

int _ColliderCount;
float4 _Colliders[8];

// RWTexture2D<float> _HiZTex;
Texture2D<float> _HiZTex;
float2 _HizTex_TexelSize;
// -------------------------------------------------------- // 


int __lodLevel(float3 positionWS)
{
    float dist = distance(positionWS, _WorldSpaceCameraPos);
    float f = 1.0 - clamp((dist - LOD_MIN_DISTANCE) / (LOD_MAX_DISTANCE - LOD_MIN_DISTANCE), 0.01, 1.00);
    f = (f*f)*(f*f);
    int lod = int(LOD_LEVELS * f);
    return lod;
}

bool FrustumCull(float3 positionWS, out float4 positionNDC)
{
    positionWS.y += _HEIGHT;

    positionNDC = mul(_ViewProj, float4(positionWS, 1.0));
    positionNDC /= positionNDC.w;
    
    const float TOLLERANCE = 0.02;
    bool isInsideFrustum = 
        positionNDC.x >= (-1.0 - TOLLERANCE) && positionNDC.x <= (1.0 + TOLLERANCE) &&
        positionNDC.y >= (-1.0 - TOLLERANCE) && positionNDC.y <= (1.0 + TOLLERANCE) &&
        positionNDC.z >= (-1.0             ) && positionNDC.z <= (1.0             );
    return !isInsideFrustum;
}

bool HiZCull(float4 positionNDC)
{
    // TODO: mipmap

    float4 pos = positionNDC*0.5 + 0.5;

    // #if UNITY_UV_STARTS_AT_TOP
    // float2 texCoord = float2(pos.x, 1.0 - pos.y);
    // #else
    // float2 texCoord = pos.xy;
    // #endif

    float sampledDepth = _HiZTex[pos.xy * _HizTex_TexelSize].r;

#ifdef SHADER_API_D3D11
    #define _DX 1
#endif

#ifdef SHADER_API_D3D11_9X
    #define _DX 1
#endif

#ifdef SHADER_API_GLCORE
    #define _GL 1
#endif

#ifdef SHADER_API_GLES
    #define _GL 1
#endif

#ifdef SHADER_API_GLES3
    #define _GL 1
#endif


const float BIAS = 0.005;

#ifdef _DX
    float z = pos.z;
    z = 1.0 - z;   // UNITY_REVERSED_Z
    return z < sampledDepth-BIAS;
#endif

#ifdef _GL
    float z = pos.z;
    return z > sampledDepth+BIAS;
#endif

    // SHADER_API_METAL, SHADER_API_VULKAN, SHADER_API_DESKTOP, SHADER_API_MOBILE, ...
    return true;  // discard all

}


float3x3 _AngleAxis3x3(float angle, float3 axis)
{
    float c, s;
    sincos(angle, s, c);

    float t = 1 - c;
    float x = axis.x;
    float y = axis.y;
    float z = axis.z;

    return float3x3(
    t * x * x + c, t * x * y - s * z, t * x * z + s * y,
    t * x * y + s * z, t * y * y + c, t * y * z - s * x,
    t * x * z - s * y, t * y * z + s * x, t * z * z + c);
}

float3x3 AngleAxis3x3(float angle, float3 axis)
{
    angle = clamp(angle, -HALF_PI, HALF_PI);
    return _AngleAxis3x3(angle, axis);
}


void GrassGen(float3 positionWS, uint3 uid) {
    GrassData data;
    data.lod = __lodLevel(positionWS);
    data.positionWS = positionWS;

    // data.lod = 3;  // disable lod

    const int _NUM_BLADES = ((data.lod >= LOD_MAX) ? (LOD_MAX+(LOD_MAX>>1)) : 
                             ((data.lod <= LOD_MIN) ? (((uid.x^uid.y) & 3) ? 0 : 1)  // xor for more randomness
                             : max(data.lod-1, 1)));
    if (_NUM_BLADES == 0) return;

    const int _NUM_SEGS = max(data.lod-1, 0);
    const float _BODY_H = _HEIGHT / (float)(_NUM_SEGS + 1);
    int _REAL_NUM_BLADES = 0;

    for (int i = 0; i < _NUM_BLADES; i++) { // blades
        float3 rnd = rand3(data.positionWS+i) * 2 - 1;
        float2 cs = float2(sin(rnd.z*PI), cos(rnd.z*PI));
        float3 right    = float3( cs.x, 0, cs.y);
        float3 normalWS = float3(-cs.y, 0, cs.x);
        float3 v0 = data.positionWS + float3(rnd.x, 0, rnd.y) * _DIST_RANGE - float3(0, _BASE_P, 0);
        float3 vM = v0;
        vM.y += _HEIGHT;

        TriangleData tri;
        VertexData vert;
        
        float lod = (float)data.lod;
        tri.color = rand3(float3(lod, lod+2, lod+3));

        // collision >>> 
        float coWeight = 1.0;
        float coDirection = 0.0;
        
        for (int c = 0; c < _ColliderCount; c++)
        {
            float3 coD = _Colliders[c].xyz - v0;
            float coL = length(coD);
            float coR = _Colliders[c].w;
            
            const float _CO_MARGIN = min(coR*2, 1.0);

            float coWeightTmp = smoothstep(0.0, _CO_MARGIN, coL-coR) / _CO_MARGIN;

            if (coWeightTmp < coWeight) {
                coWeight = coWeightTmp;
                coDirection = -(float)(sign(dot(normalWS, coD)));
                if (coDirection == 0.0) coDirection = 1.0;
            }
        }
        if (coWeight < 0.01) continue;  // discard

        float coCurve = coDirection * 0.5 * HALF_PI * (1.0 - coWeight);

        // <<< collision

        // curvation >>>
        const float _Frequency = 1.5;
        const float _WaveWidth = 0.3;
        float2 dir = (_WaveWidth*data.positionWS.xz - _Frequency*_Time) * _Wind.xz + rnd.xz * 0.8;
        float randomWave = sin(abs(fmod(dir.x + dir.y, PI)));  // simulate sharp wave

        const float _WindIntensity = 0.7;
        float windWave = _WindIntensity * sign(dot(_Wind, normalWS));

        float curvation = (randomWave + 0.5) * windWave;
        // <<< curvation

        float w1 = (float)(0)/(float)(_NUM_SEGS+2);
        float w2 = (float)(1)/(float)(_NUM_SEGS+2);
        float3x3 rot1 = AngleAxis3x3(w1*curvation + coCurve, right);
        float3x3 rot2 = AngleAxis3x3(w2*curvation + coCurve, right);
        float3 n1 = mul(rot1, normalWS);
        float3 n2 = mul(rot2, normalWS);
        
        float3 baseOffset = right*_WIDTH;
        float3 deltaOffset = baseOffset / (float)(_NUM_SEGS+2);
        
        float3 v1 = v0 + baseOffset + float3(0, _BASE_H, 0);
        float3 v2 = v0 - baseOffset + float3(0, _BASE_H, 0);

        // vert.normalWS = n1; vert.weight = w1; vert.positionWS = v0; tri.vertices[0] = vert;
        // vert.normalWS = n2; vert.weight = w2; vert.positionWS = v1; tri.vertices[1] = vert;
        // vert.normalWS = n2; vert.weight = w2; vert.positionWS = v2; tri.vertices[2] = vert;
        // _Triangles.Append(tri);

        for (int j = 0; j < _NUM_SEGS; j++) {  // segments
            w1 = w2;
            w2 = (float)(j+2)/(float)(_NUM_SEGS+2);
            rot1 = rot2;
            rot2 = AngleAxis3x3(w2*curvation + coCurve, right);
            n1 = n2;
            n2 = mul(rot2, normalWS);
            float3 offset = mul(rot2, float3(0, _BODY_H, 0));

            float3 v3 = v1 - deltaOffset + offset;
            float3 v4 = v2 + deltaOffset + offset;

            vert.normalWS = n1; vert.weight = w1; vert.positionWS = v1; tri.vertices[0] = vert;
            vert.normalWS = n1; vert.weight = w1; vert.positionWS = v2; tri.vertices[2] = vert;
            vert.normalWS = n2; vert.weight = w2; vert.positionWS = v3; tri.vertices[1] = vert;
            _Triangles.Append(tri);

            vert.normalWS = n1; vert.weight = w1; vert.positionWS = v2; tri.vertices[0] = vert;
            vert.normalWS = n2; vert.weight = w2; vert.positionWS = v3; tri.vertices[1] = vert;
            vert.normalWS = n2; vert.weight = w2; vert.positionWS = v4; tri.vertices[2] = vert;
            _Triangles.Append(tri);

            v1 = v3;
            v2 = v4;
        }

        float wH = 1.0;  // ((float)(_NUM_SEGS+2)/(float)(_NUM_SEGS+2))
        float3x3 rot3 = AngleAxis3x3(wH*curvation + coCurve, right);

        float3 vH = v1 + mul(rot3, float3(0, _BODY_H, 0)) - deltaOffset;
        vert.normalWS = n2; vert.weight = w2; vert.positionWS = v1; tri.vertices[0] = vert;
        vert.normalWS = n2; vert.weight = w2; vert.positionWS = v2; tri.vertices[2] = vert;
        vert.normalWS = n2; vert.weight = wH; vert.positionWS = vH; tri.vertices[1] = vert;
        _Triangles.Append(tri);

        _REAL_NUM_BLADES += 1;
    }
    InterlockedAdd(_IndirectArgsBuffer[0].numVerticesPerInstance, _REAL_NUM_BLADES * (_NUM_SEGS * 2 + 1) * 3);
}

#endif