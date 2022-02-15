Shader "Custom/Layered_BRDF" 
{
	Properties 
	{
		[Header(Base Properties)]
    	[Space(10)]
        [MainColor] _Color			("Color", Color)					= (1, 1, 1, 1)
        [MainTexture]	_MainTex	("Albedo (RGB)", 2D)				= "white" {}
		[Normal]		_Normal		("Normal", 2D)						= "bump" {}
		_Ambient_occlusion			("Ambient Occullsion", Range(0,1))	= 1.0
		[NoScaleOffset] _BRDFLut	("BRDF LUT", 2D)					= "white" {}

		[Space(5)]
	    [Header(Toggles)]
    	[Space(10)]
	    [Toggle] _Enable_IBL	("Enable Image Based Lighting", Range(0,1))	= 0
    	[Toggle] _Flip_norm		("Flip normal maps y axis", Range(0,1))		= 0
		[Toggle] _Enable_Oren	("Enable Oren-nayar diffuse", Range(0,1))	= 0
		
		[Space(15)]
		[Header(Vanish Properties)]
    	[Space(10)]
		_vanish		("Vanish colour", Color)			= (0, 0, 0, 1)
		_density	("Vanish thickness", Range(0, 15))	= 0.0
        
		[Space(15)]
		[Header(Top Layer Properties)]
    	[Space(10)]
		_l1_RoughTex	("Layer 1 Roughness", 2D)				= "white" {}
		_l1_MetalTex	("Layer 1 Metal", 2D)					= "white" {}
		_l1_specular	("Specular", Range(0,1))				= 0.5
		_l1_metallic	("Metallic", Range(0,1))				= 0.0
		_l1_roughness	("Roughness", Range(0,1))				= 0.0
		_l1_ior			("Index of Refraction", Range(1, 3))	= 1.33
		
		[Space(15)]
        [Header(Bottom Layer Properties)]
    	[Space(10)]
		_l2_RoughTex	("Layer 2 Roughness", 2D)				= "white" {}
		_l2_MetalTex	("Layer 2 Metal", 2D)					= "white" {}
		_l2_specular	("Specular", Range(0,1))				= 0.5
		_l2_metallic	("Metallic", Range(0,1))				= 0.0
		_l2_roughness	("Roughness", Range(0,1))				= 0.0
		_l2_ior			("Index of Refraction", Range(1, 3))	= 1.085
	}
	SubShader 
	{
		Pass
		{
			// Pass_Properties
			Name "Physically Based Rendering with multi-layered brdf"
			Tags { "RenderType" = "Opaque" "LightMode" = "ForwardBase" }
			LOD 200
			
			HLSLPROGRAM
			#pragma target 3.0

			// Unity includes
			#include "UnityCG.cginc"
			#include "AutoLight.cginc"
            #include "Lighting.cginc"
			#include "UnityLightingCommon.cginc"

			// Custom includes
			#include "Assets/Shaders/Includes/PBR.cginc"
			#include "Assets/Shaders/Includes/Vertex.cginc"

			// Vertex and pixel shader declares
			#pragma vertex vert
			#pragma fragment frag

			//--------------------------------------------------
			// Vertex_Shader
			vertex_output vert(appdata_full v) // appdata_full contains: position, tangent, normal, four texture coordinates and color
			{
				vertex_output output;

				// Base Properties
				output.position			= UnityObjectToClipPos(v.vertex);
				output.normal			= UnityObjectToWorldNormal(v.normal);
				output.uv				= float4(v.texcoord.xy, 0.0f, 0.0f);
				output.tangent			= float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
				output.world_position	= mul(unity_ObjectToWorld, v.vertex).xyz;

				// Unity fog and shadows
				UNITY_TRANSFER_FOG(output, output.position);
				TRANSFER_VERTEX_TO_FRAGMENT(output); // Misleading name. Its transfer data for shadows
				
				return output;
			}

			// Pixel Shader variables
			sampler2D _MainTex, _Normal, _BRDFLut, _l1_RoughTex, _l2_RoughTex, _l1_MetalTex, _l2_MetalTex;
			float4 _MainTex_ST, _Normal_ST, _l1_RoughTex_ST, _l2_RoughTex_ST, _l1_MetalTex_ST, _l2_MetalTex_ST; // Scale and transform
			fixed4 _Color, _vanish;
			half _Ambient_occlusion; // Base property
			half _l1_specular, _l1_metallic, _l1_roughness; // Layer 1 properties
			half _l2_specular, _l2_metallic, _l2_roughness, _density, _l1_ior, _l2_ior; // Layer 2 properties
			half _Enable_IBL, _Flip_norm, _Enable_Oren; // Toggles

			//--------------------------------------------------
			// Pixel shader
			half4 frag(vertex_output input) : SV_Target
			{
				// Lighting information
				UnityLight lighting;
				lighting.dir = normalize(_WorldSpaceLightPos0.xyz);
				lighting.color = _LightColor0.rgb * LIGHT_ATTENUATION(input);
				
				// Base material albedo
				material_properties base_material;
				base_material.albedo = tex2D(_MainTex, uv_transform(input.uv, _MainTex_ST)) * _Color;

				// Base material normal
				fixed3 normal = UnpackNormal(tex2D(_Normal, uv_transform(input.uv, _Normal_ST)));
				normal = lerp(normal, flip_normal_y_axis(normal), _Flip_norm);
				base_material.normal = calculate_normal_map(normal, input.tangent, input.normal);

				//--------------------------------------------------
				// Layer 1
				material_properties layer_1;
				layer_1.roughness	= tex2D(_l1_RoughTex, uv_transform(input.uv, _l1_RoughTex_ST)) * remap_roughness(_l1_roughness);
				layer_1.metallic	= tex2D(_l1_MetalTex, uv_transform(input.uv, _l1_MetalTex_ST)) * _l1_metallic;
				layer_1.ior			= remap_ior(_l1_ior);

				// layer 1 Normal incidence
				half3 l1_f0 = layer_1.ior; // float3(0.04f, 0.04f, 0.04f) https://inspirnathan.com/posts/58-shadertoy-tutorial-part-12/
				l1_f0 = lerp(l1_f0, pow(base_material.albedo, 2.2h), layer_1.metallic);

				// Layer 1 View direction | Half vector | Reflection direction
				const half3 view_dir		= normalize(UnityWorldSpaceViewDir(input.world_position));
				const half3 half_vector		= normalize(view_dir + lighting.dir);
				const half3 reflection_dir	= normalize(reflect(-view_dir, base_material.normal));
				
				// Layer 1 dot product
				const half l1_n_dot_l = saturate(dot(base_material.normal, lighting.dir));
				const half l1_n_dot_h = saturate(dot(base_material.normal, half_vector));
				const half l1_n_dot_v = saturate(dot(base_material.normal, view_dir));
				const half l1_v_dot_h = saturate(dot(view_dir, half_vector));

				// Top layer
				brdf top_layer;
				top_layer.n = trowbridge_reitz_ggx(l1_n_dot_h, layer_1.roughness);
				top_layer.g = sqr(geometry_smith(l1_n_dot_v, l1_n_dot_l, layer_1.roughness));
				top_layer.f = fresnel_schlick(l1_v_dot_h, l1_f0, 1.0f);
				half3 fr1	= cook_torrance_brdf(top_layer, l1_n_dot_v, l1_n_dot_l) * _l1_specular; // Layer 1 specular

				const half3 layer1_ks	= top_layer.f;
				half3 layer1_kd			= 1.0h - layer1_ks;
				layer1_kd				*= 1.0h - layer_1.metallic;
				
				//--------------------------------------------------
				// Layer 2
				material_properties layer_2;
				layer_2.roughness	= tex2D(_l2_RoughTex, uv_transform(input.uv, _l2_RoughTex_ST)) * remap_roughness(_l2_roughness);
				layer_2.metallic	= tex2D(_l2_MetalTex, uv_transform(input.uv, _l2_MetalTex_ST)) * _l2_metallic;
				layer_2.ior			= remap_ior(_l2_ior);
				
				// layer 2 Normal incidence
				half3 l2_f0 = layer_2.ior; // float3(0.04f, 0.04f, 0.04f)
				l2_f0 = lerp(l2_f0, pow(base_material.albedo, 2.2h), layer_2.metallic);

				// Layer 2 Refracted View direction | Half vector | Reflection direction
				const half n = 1.0h / 1.25h;
				const half3 refract_view = -refract(view_dir, base_material.normal, n);
				const half3 refract_light = -refract(lighting.dir, base_material.normal, n);
				const half3 refract_half = normalize(refract_view + refract_light);
				
				// Layer 2 dot product
				const half l2_n_dot_l = saturate(dot(base_material.normal, refract_light));
				const half l2_n_dot_h = saturate(dot(base_material.normal, refract_half));
				const half l2_n_dot_v = saturate(dot(base_material.normal, refract_view));
				const half l2_v_dot_h = saturate(dot(refract_view, refract_half));
				
				// Bottom Layer
				brdf bottom_layer;
				bottom_layer.n = trowbridge_reitz_ggx(l2_n_dot_h, layer_2.roughness);
				bottom_layer.g = sqr(geometry_smith(l2_n_dot_v, l2_n_dot_l, layer_2.roughness));
				bottom_layer.f = fresnel_schlick(l2_v_dot_h, l2_f0, 1.0f);
				half3 fr2 = cook_torrance_brdf(bottom_layer, l2_n_dot_v, l2_n_dot_l) * _l2_specular; // Layer 2 specular

				const half3 layer2_ks = bottom_layer.f;
				half3 layer2_kd = 1.0h - layer2_ks;
				layer2_kd *= 1.0h - layer_2.metallic;

				//--------------------------------------------------
				// Combining both layers
				
				// Fresnel transmission
				const half g = top_layer.g;
				const half3 f = top_layer.f;
				const half3 t12 = 1.0h - f;			// Fresnel transmission from layer 1 to layer 2
				const half3 t21 = t12;					// Fresnel transmission from layer 2 to layer 1
				const half3 t = (1.0h - g) + t21 * g;	// Internal reflection

				// Absorption term
				const half l = _density * (1.0h / l2_n_dot_l + 1.0h / l2_n_dot_v);
				const half3 absorption = exp(-_vanish * l);

				// Ambient and Diffuse
				const half3 ambient = calculate_ambient_light(base_material.albedo, _Ambient_occlusion);
				const half3 lambert = (1.0h - bottom_layer.f) * lambert_diffuse(base_material.albedo, lighting.color, 1.0h);
				const half3 oren = (1.0h - bottom_layer.f) * OrenNayar(base_material.albedo, lighting, base_material.normal, refract_view, layer_2.roughness);
				const half3 diffuse = lerp(lambert, oren, _Enable_Oren);

				// Combined Layer Specular
				const half3 fr = (fr1 + t12 * fr2 * absorption * t);

				const half3 kd = lerp(layer1_kd, layer2_kd, t12 * t);
				
				// Composition
				const half3 outgoing_radiance = (kd * diffuse * absorption + fr) * l1_n_dot_l;
				const half3 color = ambient + outgoing_radiance;

				//--------------------------------------------------
				// Layer 1 Image Based Lighting
				
				// Image Based Lighting - Roughness
				const half3 l1_ks_2 = fresnel_schlick_roughness(l1_n_dot_v, l1_f0, layer_1.roughness);
				half3 l1_kd_2 = 1.0h - l1_ks_2;
				l1_kd_2 *= 1.0h - layer_1.metallic;

				// Image Based Lighting - Indirect Diffuse
				const half3 indirect_diffuse = evaluate_diffuse_ibl(base_material.normal) * base_material.albedo;
				
				// Image Based Lighting - Indirect Specular
				Unity_GlossyEnvironmentData env_data;
				env_data.roughness = layer_1.roughness;
				env_data.reflUVW = reflection_dir;
				
				const half3 fr1_env = fresnel_schlick(l1_n_dot_v, layer_1.ior, 1.0h);
				const half2 brdf_lut = tex2D(_BRDFLut, half2(l1_n_dot_v, layer_1.roughness)).rg;
				half3 indirect_specular = fr1_env * evaluate_specular_ibl(env_data, l1_ks_2, brdf_lut);

				// Image Based Lighting - composition
				const half3 ambient_ibl = (l1_kd_2 * indirect_diffuse + indirect_specular) * _Ambient_occlusion;
				const half3 color_ibl = outgoing_radiance + ambient_ibl;

				// Output is changed based on if Image Based Lighting is enabled
				return half4(lerp(color, color_ibl, _Enable_IBL), 1.0h);
			}
			ENDHLSL
		}
	}
	FallBack "Legacy Shaders/Diffuse"
}