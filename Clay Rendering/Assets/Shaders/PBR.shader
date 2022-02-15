Shader "Custom/PBR"
{
	//--------------------------------------------------
	// A shader that renders physically based materials
	
    Properties
    {
	    [Header(Textures)]
    	[Space(10)]
        [MainTexture] _MainTex		("Albedo (RGB)", 2D)	= "white" {}
		[Normal] _NormalTex			("Normal Map", 2D)		= "bump" {}
	    _RoughTex					("Roughness map", 2D)	= "white" {}
    	_MetalTex					("Metallic map", 2D)	= "white" {}
	    [NoScaleOffset] _BRDFLut	("BRDF LUT", 2D)		= "white" {}
    	
	    [Space(5)]
	    [Header(Toggles)]
    	[Space(10)]
	    [Toggle] _Enable_IBL	("Enable Image Based Lighting", Range(0,1))	= 0
    	[Toggle] _Flip_norm		("Flip normal maps y axis", Range(0,1))		= 0
    	
    	[Space(5)]
    	[Header(PBR properties)]
    	[Space(10)]
    	[MainColor] _Color	("Color / Tint", Color)					= (1,1,1,1)
	    _ior				("Index of Refraction", Range(1,3))		= 1.085
        _Specular			("Specular", Range(0,1))				= 0.5
    	_Roughness			("Roughness", Range(0,1))				= 1.0
        _Metallic			("Metallic", Range(0,1))				= 0.0
    	_Ambient_occlusion	("Ambient Occullsion", Range(0,1))		= 1.0
    }
    SubShader
    {
		Pass
		{
			// Pass_Properties
			Name "Physically Based Rendering"
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
			#include "Assets/Shaders/Includes/PBR.cginc" //<-this includes brdf.cginc and Functions.cginc
			#include "Assets/Shaders/Includes/Vertex.cginc" 

			// Vertex and pixel shader declares
			#pragma vertex vert
			#pragma fragment frag

			//--------------------------------------------------
			// Vertex_Shader
			vertex_output vert(appdata_full v) // appdata_full contains: position, tangent, normal, four texture coordinates and color
			{
				vertex_output output;
				output.position			= UnityObjectToClipPos(v.vertex);
				output.normal			= UnityObjectToWorldNormal(v.normal);
				output.uv				= float4(v.texcoord.xy, 0.0f, 0.0f);
				output.tangent			= float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
				output.world_position	= mul(unity_ObjectToWorld, v.vertex).xyz;

				// Unity fog and shadows
				UNITY_TRANSFER_FOG(output, output.position);
				TRANSFER_VERTEX_TO_FRAGMENT(output); // Misleading name. Its transfer light coords and shadows
				
				return output;
			}
			
			// Pixel Shader variables
			sampler2D _MainTex, _NormalTex, _BRDFLut, _RoughTex, _MetalTex;
			float4 _MainTex_ST, _NormalTex_ST, _RoughTex_ST, _MetalTex_ST;
			fixed4 _Color;
			half _Metallic, _Roughness, _ClearCoat, _ClearCoatGloss, _ior, _Ambient_occlusion, _Specular, _DetailedNormAmount;
			half _Enable_IBL, _Flip_norm;
			
			//--------------------------------------------------
			// Pixel_Shader
			half4 frag(const vertex_output input) : SV_Target
			{
				// normalize(lerp(_WorldSpaceLightPos0.xyz, _WorldSpaceLightPos0.xyz - input.world_position.xyz, _WorldSpaceLightPos0.w));
				
				// Lighting information
				UnityLight lighting;
				lighting.dir	= normalize(_WorldSpaceLightPos0.xyz);
				lighting.color	= _LightColor0.rgb * LIGHT_ATTENUATION(input);
				
				material_properties material;

				material.albedo = tex2D(_MainTex, uv_transform(input.uv, _MainTex_ST)) * _Color; // Albedo | BaseColor | Diffuse

				half3 normal_tex = UnpackNormal(tex2D(_NormalTex, uv_transform(input.uv, _NormalTex_ST))); // Normal Map

				// Flips normal map y axis based on artist choice
				// This is only done if the provided normal maps are directX based and not OpenGL
				normal_tex = lerp(normal_tex, flip_normal_y_axis(normal_tex), _Flip_norm);

				// Create normal map
				material.normal	= calculate_normal_map(normal_tex, input.tangent, input.normal);
				
				// Material Properties
				material.specular			= _Specular + SPECULAR_OFFSET; // Offset added to keep specular in 0-1 range
				material.roughness			= tex2D(_RoughTex, uv_transform(input.uv, _RoughTex_ST)).r * remap_roughness(_Roughness);
				material.metallic			= tex2D(_MetalTex, uv_transform(input.uv, _MetalTex_ST)).r * _Metallic;
				material.ambient_occlusion	= _Ambient_occlusion;
				material.ior				= remap_ior(_ior);
				material.clear_coat			= _ClearCoat;
				material.clear_coat_gloss	= _ClearCoatGloss;

				// View direction | half vector | reflection direction
				const half3 view_dir		= normalize(UnityWorldSpaceViewDir(input.world_position));
				const half3 half_vector		= normalize(view_dir + lighting.dir);
				const half3 reflection_dir	= normalize(reflect(-view_dir, material.normal));
				
				// Dot products
				const half n_dot_l = saturate(dot(material.normal, lighting.dir));	// Dot product of normal and light
				const half n_dot_h = saturate(dot(material.normal, half_vector));	// Dot product of normal and half vector
				const half n_dot_v = saturate(dot(material.normal, view_dir));		// Dot product of normal and view
				const half l_dot_h = saturate(dot(lighting.dir, half_vector));		// Dot product of light and half vector
				
				// Calculate normal incidence
				half3 f0 = material.ior; // half3(0.04h, 0.04h, 0.04h);
				f0 = lerp(f0, pow(material.albedo, 2.2h), material.metallic);

				// Cook-torrance bi-directional reflectance distribution function
				brdf cook_brdf;
				cook_brdf.n = trowbridge_reitz_ggx(n_dot_h, material.roughness);
				cook_brdf.g = sqr(geometry_smith(n_dot_v, n_dot_l, material.roughness));
				cook_brdf.f = fresnel_schlick(n_dot_l, f0, 1.0h);

				const half3 ks = cook_brdf.f;
				half3 kd = 1.0h - ks;
				kd *= 1.0h - material.metallic;

				// Clear coat gloss
				const half clear_coat_spec = disney_clear_coat(n_dot_l, n_dot_v, n_dot_h, l_dot_h, material);

				// Specular
				const half3 specular = cook_torrance_brdf(cook_brdf, n_dot_v, n_dot_l) * material.specular;
				const half3 outgoing_radiance = (kd * lambert_diffuse(material.albedo, lighting.color, 1.0h) + (specular + clear_coat_spec)) * n_dot_l;

				// Composition
				const half3 ambient = calculate_ambient_light(material.albedo, material.ambient_occlusion);
				const half3 color = ambient + outgoing_radiance;

				// Gamma correction
				//color = gamma_correction(color);

				// Image Based Lighting - Roughness
				const half3 ks_2 = fresnel_schlick_roughness(n_dot_v, f0, material.roughness);
				half3 kd_2 = 1.0h - ks_2;
				kd_2 *= 1.0h - material.metallic;

				// Image Based Lighting - Indirect Diffuse
				const half3 indirect_diffuse = evaluate_diffuse_ibl(material.normal) * material.albedo.rgb;

				// Image Based Lighting - Indirect Specular
				Unity_GlossyEnvironmentData env_data;
				env_data.roughness = material.roughness;
				env_data.reflUVW = reflection_dir;
				
				const half2 brdf_lut = tex2D(_BRDFLut, half2(0.5h /* n_dot_v*/, material.roughness)).rg;
				const half3 indirect_specular = evaluate_specular_ibl(env_data, ks_2, brdf_lut);

				// Image Based Lighting - composition
				const half3 ambient_IBL = (kd_2 * indirect_diffuse + indirect_specular) * material.ambient_occlusion;
				const half3 color_IBL = ambient_IBL + outgoing_radiance;

				// Gamma correction
				// color_IBL = gamma_correction(color_IBL);
				
				// Output is changed based on if Image Based Lighting is enabled
				return half4(lerp(color, color_IBL, _Enable_IBL), 1.0h);
			}
			ENDHLSL
		}
    }
    FallBack "Legacy Shaders/Diffuse"
}
