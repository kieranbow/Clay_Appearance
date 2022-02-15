Shader "Custom/PBR_ClearCoat"
{
	//--------------------------------------------------
	// A shader that renders physically based materials with Disney's Clear Coat Gloss
	
    Properties
    {
	    [Header(Textures)]
    	[Space(10)]
    	[MainTexture] _MainTex		("Albedo (RGBA)", 2D)	= "white" {}
    	[Normal] _NormalTex			("Normal Map (xyz)", 2D)= "bump" {}
    	_RoughTex					("Roughness map", 2D)	= "white" {}
    	_MetalTex					("Metallic map", 2D)	= "white" {}
    	[NoScaleOffset] _BRDFLut	("BRDF Look up", 2D)	= "white" {}
    	
	    [Space(5)]
	    [Header(Toggles)]
    	[Space(10)]
	    [Toggle] _Enable_IBL	("Enable Image Based Lighting", Range(0,1))	= 0
    	[Toggle] _Flip_norm		("Flip normal maps y axis", Range(0,1))		= 0
    	
    	[Space(5)]
	    [Header(PBR Properties)]
    	[Space(10)]
        [MainColor] _Color	("Color / Tint", Color)				= (1,1,1,1)
	    _Roughness			("Roughness", Range(0,1))			= 1.0
        _Metallic			("Metallic", Range(0,1))			= 0.0
    	_Specular			("Specular", Range(0,1))			= 0.5
    	_Ambient_occlusion	("Ambient Occullsion", Range(0,1))	= 1.0
    	
	    [Space(5)]
	    [Header(Clear Coat Properties)]
    	[Space(10)]
		_ClearCoat			("Clear Coat", Range(0,1))			= 0.0
		_ClearCoatGloss		("Cloar Coat Gloss", Range(0,1))	= 0.0
    	_ior				("Index of Refraction", Range(1,3))	= 1.33
    }
    SubShader
    {
		Pass
		{
			// Pass_Properties
			Name "Physically Based Rendering with clear coat"
			Tags { "RenderType" = "Opaque" "LightMode" = "ForwardBase" }
			LOD 200

			HLSLPROGRAM
			#pragma target 3.0

			// Unity include
			#include "UnityCG.cginc"
			#include "AutoLight.cginc"
            #include "Lighting.cginc"
			#include "UnityLightingCommon.cginc"
			
			// Custom includes
			#include "Assets/Shaders/Includes/PBR.cginc" //<-this includes brdf.cginc and Functions.cginc
			#include "Assets/Shaders/Includes/Vertex.cginc" 
			
			// Unity's vertex & fragment functions
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
			sampler2D _MainTex, _NormalTex, _BRDFLut, _RoughTex, _MetalTex; // Texture samples
			float4 _MainTex_ST, _NormalTex_ST, _RoughTex_ST, _MetalTex_ST; // Texture scale and transforms
			fixed4 _Color;
			half _Metallic, _Roughness, _ClearCoat, _ClearCoatGloss, _Ambient_occlusion, _Specular, _ior; // PBR properties
			half _Enable_IBL, _Flip_norm; // Toggles
			
			//--------------------------------------------------
			// Pixel_Shader
			half4 frag(vertex_output input) : SV_Target
			{
				// Lighting information
				UnityLight lighting;
				lighting.dir = normalize(_WorldSpaceLightPos0.xyz);
				lighting.color = _LightColor0.rgb * LIGHT_ATTENUATION(input);
				
				material_properties material;

				// Albedo | BaseColor | Diffuse
				material.albedo = tex2D(_MainTex, input.uv * _MainTex_ST.xy + _MainTex_ST.zw) * _Color;

				// Normal Map
				half3 normal_tex = UnpackNormal(tex2D(_NormalTex, uv_transform(input.uv, _NormalTex_ST)));

				// Flips normal map y axis based on artist choice
				// This is only done if the provided normal maps are directX based and not OpenGL
				normal_tex = lerp(normal_tex, flip_normal_y_axis(normal_tex), _Flip_norm);
				
				// Create normal map
				material.normal				= calculate_normal_map(normal_tex, input.tangent, input.normal);
				material.specular			= _Specular + SPECULAR_OFFSET; // Offset added to keep specular in 0-1 range
				material.roughness			= tex2D(_RoughTex, uv_transform(input.uv, _RoughTex_ST)).r * remap_roughness(_Roughness);
				material.metallic			= tex2D(_MetalTex, uv_transform(input.uv, _MetalTex_ST)).r * _Metallic;
				material.ambient_occlusion	= _Ambient_occlusion;
				material.ior				= remap_ior(_ior);

				// Clear coat
				material.clear_coat = _ClearCoat;
				material.clear_coat_gloss = _ClearCoatGloss;

				// View direction | Half vector | Reflection direction
				const half3 view_dir = normalize(UnityWorldSpaceViewDir(input.world_position));
				const half3 half_vector = normalize(view_dir + lighting.dir);
				const half3 reflection_dir = normalize(reflect(-view_dir, material.normal));
				
				// Dot products
				const half n_dot_l = max(dot(material.normal, lighting.dir), 0.0f);	// Dot product of normal and light
				const half n_dot_h = max(dot(material.normal, half_vector), 0.0f);	// Dot product of normal and half vector
				const half n_dot_v = max(dot(material.normal, view_dir), 0.0f);		// Dot product of normal and view
				const half l_dot_h = max(dot(lighting.dir, half_vector), 0.0f);		// Dot product of light and half vector
				
				// Calculate normal incidence
				half3 f0 = half3(0.04h, 0.04h, 0.04h);
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
				const half3 specular = cook_torrance_brdf(cook_brdf, n_dot_v, n_dot_l);
				const half3 outgoing_radiance = (kd * material.albedo / pi + ((specular + clear_coat_spec) * material.specular)) * lighting.color *  n_dot_l;

				// unity_SHAr contains data for spherical harmonic.
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

				// Using Unity_GlossyEnvironment is pretty much the same as UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflection_dir, roughness * UNITY_SPECCUBE_LOD_STEPS);
				const half3 indirect_spec_cube = Unity_GlossyEnvironment(UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, env_data);
				const half2 brdf_lut = tex2D(_BRDFLut, half2(0.5h /* n_dot_v*/, material.roughness)).rg;
				const half3 indirect_specular = indirect_spec_cube * (ks_2 * brdf_lut.x + brdf_lut.y);
				
				const half3 ambient_ibl = (kd_2 * indirect_diffuse + indirect_specular) * material.ambient_occlusion;
				const half3 color_ibl = ambient_ibl + outgoing_radiance;

				// Gamma correction
				// color_IBL = gamma_correction(color_IBL);
				
				// Output is changed based on if Image Based Lighting is enabled
				return half4(lerp(color, color_ibl, _Enable_IBL), 1.0h);
			}
			ENDHLSL
		}
    }
    FallBack "Legacy Shaders/Diffuse"
}
