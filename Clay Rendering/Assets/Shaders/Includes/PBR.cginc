//--------------------------------------------------
// Main file allowing for physically based rendering

// Declares
#define DIFFUSE_MIP_LEVEL 5
#define SPECULAR_OFFSET 0.5

// Includes
#include "brdf.cginc"
#include "Functions.cginc"

//--------------------------------------------------
// Structs

// A struct that contains properties which define a physically based material
struct material_properties
{
    half4 albedo;
    half3 normal;
    half specular;
    half roughness;
    half metallic;
    half ambient_occlusion;
    half ior;
    half clear_coat;
    half clear_coat_gloss;
};

// Contains the three main functions for a bi-directional reflectance distribution function.
struct brdf
{
    half n;   // Normal Distribution Function
    half g;   // Geometry Shading Function
    half3 f;  // Fresnel Function
};

struct layer
{
    half3 F0;       //Normal incidence
    half n_dot_l;   // Dot product of normal and light
    half n_dot_h;   // Dot product of normal and half vector
    half n_dot_v;   // Dot product of normal and view
    half v_dot_h;   // Dot product of light and half vector
};

//--------------------------------------------------
// Remapping functions

// Remaps ior values to a value more usable value for shaders
// Example = water(1.33) -> 0.25
half3 remap_ior(const half ior)
{
    // https://docs.blender.org/manual/en/latest/render/shader_nodes/shader/principled.html
    //return ((ior - 1.0f) / (ior + 1.0f) * (ior - 1.0f) / (ior + 1.0f)) / 0.08f;

    return (ior - 1.0h) / (ior + 1.0h);
}

// Remaps the roughness value based on Unity's remapping of roughness
half remap_roughness(const half roughness)
{
    return clamp((1.7h - 0.7h) * roughness, 0.0h, 0.99h);  
}

//--------------------------------------------------
// Image Based Lighting

// Samples unity_SpecCube0 for diffuse irradiance
half3 evaluate_diffuse_ibl(const half3 normal)
{
    const half4 irradiance_sample = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, normal, DIFFUSE_MIP_LEVEL);
    return DecodeHDR(irradiance_sample, unity_SpecCube0_HDR);
}

// Samples unity_SpecCube0 for Indirect specular
half3 evaluate_specular_ibl(const Unity_GlossyEnvironmentData env_data, const float3 ks_2, const float2 brdf_lut)
{
    // Using Unity_GlossyEnvironment is pretty much the same as UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflection_dir, roughness * UNITY_SPECCUBE_LOD_STEPS);
    const half3 indirect_spec_cube = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, env_data);
    return indirect_spec_cube * (ks_2 * brdf_lut.x + brdf_lut.y);
}

//--------------------------------------------------
// Lighting

// Calculates ambient light based on the objects albedo, ambient occlusion and Unity's spherical harmonics
half3 calculate_ambient_light(const half3 albedo, const half ambient)
{
    // unity_SHAr contains data for spherical harmonic.
    return albedo * ambient * half3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);
}

//--------------------------------------------------
// Bi-directional Reflectance Distribution Functions

// Calculates the cook torrance specular for PBR
half3 cook_torrance_brdf(const half ndf, const half g, const half3 f, const half n_dot_v, const half n_dot_l)
{
    return (f * ndf * g) / (4.0h * n_dot_v * n_dot_l + 0.0001h);
}

// Calculates the cook torrance specular for PBR
half3 cook_torrance_brdf(const brdf brdf, const half n_dot_v, const half n_dot_l)
{
    return (brdf.f * brdf.n * brdf.g) / (4.0h * n_dot_v * n_dot_l + 0.0001h);
}

// Calculates the cook torrance specular for PBR
half3 cook_torrance_brdf(const brdf brdf, const layer _layer)
{
    return (brdf.f * brdf.n * brdf.g) / (4.0h * _layer.n_dot_v * _layer.n_dot_l + 0.0001h);
}

//--------------------------------------------------
// Clear Coat gloss

half disney_clear_coat(const half n_dot_l, const half n_dot_v, const half n_dot_h, const half l_dot_h, const material_properties material)
{
    const half gloss = lerp(0.1h, 0.001h, material.clear_coat_gloss);
    const half dr = GTR1(abs(n_dot_h), gloss);
    const half fr = lerp(material.ior /*0.04f*/, 1.0h, schlickWeight(l_dot_h));
    const half gr = sqr(geometry_smith(n_dot_v, n_dot_l, 0.25h));

    return 1.0h * material.clear_coat * fr * gr * dr;
}
