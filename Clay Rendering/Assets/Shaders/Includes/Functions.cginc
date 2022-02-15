//--------------------------------------------------
// Contains a set of general helper functions for any shader

// Declares
#define GAMMA_VALUE 2.2

// Calculate the biNormal for normal maps
// https://catlikecoding.com/unity/tutorials/rendering/part-6/
half3 calculate_bi_normal(const float3 obj_normal, const float4 obj_tangent)
{
    return cross(obj_normal, obj_tangent.xyz) * obj_tangent.w;
}

// Apply the normal map to an object using its tangents, bi_normals, normals and a normal map
// https://catlikecoding.com/unity/tutorials/rendering/part-6/
half3 calculate_normal_map(const half3 normal_map, const float4 obj_tangent, const float3 obj_normal)
{
    const float3 bi_normal = calculate_bi_normal(obj_normal, obj_tangent);
    return normalize(normal_map.x * obj_tangent + normal_map.y * bi_normal + normal_map.z * obj_normal);
}

// Flips the y axis of the normal map in case normal map is DirectX based and not OpenGl
half3 flip_normal_y_axis(const half3 normal)
{
    return half3(normal.x, -normal.y, normal.z);
}

// Increases the x,y axis of the normal map
half3 normal_map_intensity(half3 normal_tex, const half intensity)
{
    half2 tex = normal_tex.rg;
    tex *= intensity;
    return half3(tex, normal_tex.b);
}

// Desaturate color based on an intensity
half3 desaturate(const half3 color, const half intensity)
{
    const half3 desaturate = half3(0.3h, 0.59h, 0.11h);
    const half luminance = dot(color, desaturate);
    const half3 new_pixel = lerp(luminance, color, intensity);
    return new_pixel;
}

// Takes a color input and returns that input with gamma correction
half3 gamma_correction(half3 color)
{
    color = color / (color + half3(1.0h, 1.0h, 1.0h));
    color = pow(color, half3(1.0h / GAMMA_VALUE, 1.0h / GAMMA_VALUE, 1.0h / GAMMA_VALUE));
    return color;
}

// Mainly used for transforming uv using Unity's _textureName_ST
float2 uv_transform(float4 uv, float4 transform)
{
    return uv.xy * transform.xy + transform.zw;
}
