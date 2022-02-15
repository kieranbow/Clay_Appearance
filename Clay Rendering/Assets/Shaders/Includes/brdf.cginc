//--------------------------------------------------
// A collection of helper Functions for creating:
// - brdf
// - Clear Coat Gloss
// - diffuse lighting

// Declares
static float pi = 3.14159265359f;

half sqr(const half x) { return x * x; }

// Comparison function from http://www.codinglabs.net/article_physically_based_rendering_cook_torrance.aspx
float chi_ggx(const float v) { return v > 0.0f ? 1.0f : 0.0f; }

// Open-GL mix function.
float mix(const float i, const float j, const float x) { return j * x + i * (1.0f - x); }

// Dinsey's remapping of roughness
half disney_roughness(const half roughness)
{
    return (roughness + 1.0h);
}

//--------------------------------------------------
// Normal distribution functions

half trowbridge_reitz_ggx(const half n_dot_h, const half roughness)
{
    const half a = sqr(roughness);
    const half a2 = sqr(a);
    const half n_dot_h2 = sqr(n_dot_h);

    const half num = a2;
    half de_nom = (n_dot_h2 * (a2 - 1.0h) + 1.0h);
    de_nom = pi * de_nom * de_nom;

    return num / de_nom;

    // Uncomment this for a weaker roughness effect
    // return (chi_ggx(n_dot_h2) * a2) / (pi * de_nom * de_nom);
}

// Trowbridge-Reitz GGX normal distribution
float normal_distribution_ggx(const float n_dot_h, const float roughness)
{
    const float a2 = sqr(roughness);
    const float n_dot_h_sqrt = sqr(n_dot_h);

    const float tan_h_sqrt = (1.0f - n_dot_h_sqrt) / n_dot_h_sqrt;
    return (1.0f / pi) * sqr(roughness / (n_dot_h_sqrt * (a2 + tan_h_sqrt)));
}

//--------------------------------------------------
// Geometry shading function

half geometry_schlick_ggx(const half n_dot_v, const half roughness)
{
    const half r = disney_roughness(roughness); // Disney modification to remap roughness to reduce roughness 'Hotness'
    const half k = sqr(r) / 8.0h;

    const half num = n_dot_v;
    const half de_nom = n_dot_v * (1.0h - k) + k;

    return num / de_nom;
}

half geometry_smith(const half n_dot_v, const half n_dot_l, const half roughness)
{
    const half ggx1 = geometry_schlick_ggx(n_dot_v, roughness);
    const half ggx2 = geometry_schlick_ggx(n_dot_l, roughness);

    return ggx1 * ggx2;
}

//--------------------------------------------------
// Fresnel functions

half3 fresnel_schlick(const half n_dot_l, const half3 f0, const half f90)
{
    return f0 + (f90 - f0) * pow(1.0h - n_dot_l, 5.0h);
}

half3 fresnel_schlick_roughness(const half n_dot_l, const half3 f0, const half roughness)
{
    return f0 + (max(half3(1.0h - roughness, 1.0h - roughness, 1.0h - roughness), f0) - f0) * pow(1.0h - n_dot_l, 5.0h);
}

//--------------------------------------------------
// Functions for Disney Clear Coat Gloss
// https://github.com/wdas/brdf/blob/master/src/brdfs/disney.brdf

half schlickWeight(const half cos_theta)
{
    const half m = clamp(1.0h - cos_theta, 0.0h, 1.0h);
    return (sqr(m)) * (sqr(m)) * m;
}

// General Trowbridge-Reitz
half GTR1(const float n_dot_h, const float roughness)
{
    if (roughness >= 1.0h) { return 1.0h / pi; }
    
    const half a2 = sqr(roughness);
    const half t = 1.0h + (a2 - 1.0h) * sqr(n_dot_h);
    return (a2 - 1.0h) / (pi * log(a2) * t);
}

//--------------------------------------------------
// Diffuse functions

half3 lambert_diffuse(const half3 albedo, const half3 light_color, const half intensity)
{
    return albedo / pi * intensity * light_color;
}

// https://www.jordanstevenstechart.com/lighting-models
half3 half_lambert(const half3 albedo, const half n_dot_l, const half3 light_color)
{
    half half_lambert = pow(n_dot_l * 0.5h + 0.5h, 2.0h) * albedo;
    return half_lambert * light_color;
}

// https://www.jordanstevenstechart.com/lighting-models
half3 OrenNayar(const half3 albedo, const UnityLight light, const half3 normal, const float3 view_dir, const half roughness)
{
    //roughness A, Ap and B
    const half roughness2 = roughness * roughness;
    const half3 oren_nayar_fraction = roughness2 / (roughness2 + half3(0.33h, 0.13h, 0.09h));
    const half3 oren_nayar = half3(1.0h, 0.0h, 0.0h) + half3(-0.5h, 0.17h, 0.45h) * oren_nayar_fraction;
    
    //components
    const half cos_nl = saturate(dot(normal, light.dir));
    const half cos_nv = saturate(dot(normal, view_dir));
    half oren_nayar_s = saturate(dot(light.dir, view_dir)) - cos_nl * cos_nv;
    oren_nayar_s /= lerp(max(cos_nl, cos_nv), 1.0h, step(oren_nayar_s, 0.0h));
    
    //composition
    return half3(albedo / pi * cos_nl * (oren_nayar.x + albedo * oren_nayar.y + oren_nayar.z * oren_nayar_s) * light.color);
}

half3 Oren_nayar(half3 albedo, half n_dot_l, half n_dot_v, half roughness, half3 light_color)
{
    half a2 = sqr(roughness);
    
    half A = 1.0h - 0.5h * a2 / (a2 + 0.33h);
    half B = 0.45h * a2 / (a2 + 0.09h);

    half theta_r = acos(n_dot_v);
    half theta_i = acos(n_dot_l);
    half phi = theta_i - theta_r;

    half alpha = max(theta_i, theta_r);
    half beta = min(theta_i, theta_r);

    return albedo / pi * n_dot_l * (A + (B * max(0.0h, cos(phi)) * sin(alpha) * tan(beta))) * light_color;
}

// https://seblagarde.files.wordpress.com/2015/07/course_notes_moving_frostbite_to_pbr_v32.pdf#page=11&amp;zoom=auto,-265,590
float Fr_DisneyDiffuse(const float n_dot_v, const float n_dot_l, const float l_dot_h, const float roughness)
{
    const float energyBias = lerp(0.0f, 0.5f, roughness);
    const float energyFactor = lerp(1.0f, 1.0f / 1.51f, roughness);
    const float fd90 = energyBias + 2.0f * l_dot_h * l_dot_h * roughness;
    const float3 f0 = float3 (1.0f , 1.0f , 1.0f);
    const float lightScatter = fresnel_schlick(n_dot_l, f0, fd90 ).r;
    const float viewScatter = fresnel_schlick(n_dot_v, f0, fd90 ).r;

    return lightScatter * viewScatter * energyFactor ;
}


// Unused functions
float schlick_fresnel(const float i)
{
    const float x = clamp(1.0f - i, 0.0f, 1.0f);
    const float x2 = sqr(x);
    return x2 * x2 * x;
}

// normal incidence reflection calculation
float f0(const float n_dot_l, const float n_dot_v, const float l_dot_h, const float roughness)
{
    const float fresnel_light = schlick_fresnel(n_dot_l);
    const float fresnel_view = schlick_fresnel(n_dot_v);
    const float fresnel_diffuse = 0.5f + 2.0f * l_dot_h * l_dot_h * roughness;

    return lerp(1.0f, fresnel_diffuse, fresnel_light) * lerp(1.0f, fresnel_diffuse, fresnel_view);
}
