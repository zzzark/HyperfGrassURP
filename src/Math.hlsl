#ifndef MATH_HLSL
#define MATH_HLSL


#define HALF_PI 1.570796327
#define PI      3.141592653
#define TWO_PI  6.283185307


// float4 EncodeFloatRGBA(float v) {
//     float4 enc = float4(1.0, 255.0, 65025.0, 16581375.0) * v;
//     enc = frac(enc);
//     enc -= enc.yzww * float4(1.0/255.0,1.0/255.0,1.0/255.0,0.0);
//     return enc;
// }

// float DecodeFloatRGBA(float4 rgba) {
//     return dot(rgba, float4(1.0, 1/255.0, 1/65025.0, 1/16581375.0));
// }

// void EncodeFloatRGBA_float(float v, out float4 rgba) {
//     rgba = EncodeFloatRGBA(v);
// }

// uint RGBAtoUINT(float4 color)
// {
//     //uint4 bitShifts = uint4(24, 16, 8, 0);
//     //uint4 colorAsBytes = uint4(color * 255.0f) << bitShifts;

//     uint4 kEncodeMul = uint4(16777216, 65536, 256, 1);
//     uint4 colorAsBytes = round(color * 255.0f);

//     return dot(colorAsBytes, kEncodeMul);
// }

// float4 UINTtoRGBA(uint value)
// {
//     uint4 bitMask = uint4(0xff000000, 0x00ff0000, 0x0000ff00, 0x000000ff);
//     uint4 bitShifts = uint4(24, 16, 8, 0);

//     uint4 color = (uint4)value & bitMask;
//     color >>= bitShifts;

//     return color / 255.0f;
// }

// void UINTtoRGBA_float(float f_value, out float4 rgba)
// {
//     uint value = (uint)(f_value);
//     uint4 bitMask = uint4(0xff000000, 0x00ff0000, 0x0000ff00, 0x000000ff);
//     uint4 bitShifts = uint4(24, 16, 8, 0);

//     uint4 color = (uint4)value & bitMask;
//     color >>= bitShifts;

//     rgba = color / 255.0f;
// }

float rand(float3 co)
{
    return frac(sin(dot(co, float3(12.9898, 78.233, 53.539))) * 43758.5453);
}

float2 rand2(float3 co)
{
    return float2(rand(co.xyz), rand(co.yzx));
}

float3 rand3(float3 co)
{
    return float3(rand(co.xyz), rand(co.yzx), rand(co.zxy));
}

#endif
