Shader "Custom/ClayShader" 
{
	//--------------------------------------------------
	// A shader that renders physically based Clay using a multi-layered brdf
	Properties 
	{
	    [Header(Albedo and Color)]
    	[Space(10)]
		[MainColor] _Color		("Color", Color)					= (1, 1, 1, 1)
        [MainTexture] _MainTex	("Albedo (RGB)", 2D)				= "white" {}
		_Desaturate				("Desaturate color", Range(0,1))	= 1.0
		_Ambient_occlusion		("Ambient Occullsion", Range(0,1))	= 1.0
		
		[Space(15)]
	    [Header(Object Normal map)]
    	[Space(10)]
		[Normal] _NormalTex			("Normal Map", 2D)						= "bump" {}
		_Normal_intensity			("Normal map intensity", Range(0,1))	= 1.0
	    [Normal] _DetailNormalTex	("Detailed Normal Map", 2D)				= "bump" {}
		_DetailedNormAmount			("Detail normal intensity", Range(0,1))	= 1.0

		[Space(5)]
	    [Header(Toggles)]
    	[Space(10)]
	    [Toggle] _Enable_IBL	("Enable Image Based Lighting", Range(0,1))	= 0
    	[Toggle] _Flip_norm		("Flip normal maps y axis", Range(0,1))		= 0
		[Toggle] _Flip_diffuse	("Enable lambert diffuse", Range(0,1))		= 0

		[Space(15)]
		[Header(Top Layer Properties)]
    	[Space(10)]
		_layer1_RoughTex	("Roughness Texture", 2D)				= "white" {}
	    _layer1_specular	("Specular Intensity", Range(0,1))		= 0.5
	    _layer1_roughness	("Roughness Intensity", Range(0,1))		= 0.0
		_layer1_ior			("Index of Refraction", Range(1, 3))	= 1.33 // Water
		_Density			("Amount of light absorbed", Range(0,1))= 1.0
		
		[Space(15)]
        [Header(Bottom Layer Properties)]
    	[Space(10)]
		_layer2_RoughTex	("Roughness Texture", 2D)				= "white" {}
	    _layer2_specular	("Specular Intensity", Range(0,1))		= 0.5
	    _layer2_roughness	("Roughness Intensity", Range(0,1))		= 0.0
		_layer2_ior			("Index of Refraction", Range(1, 3))	= 1.085
	    
		[Space(15)]
	    [Header(Misc)]
    	[Space(10)]
	    [NoScaleOffset] _BRDFLut ("BRDF LUT", 2D) = "white" {}
	}
	SubShader 
	{
		Pass
		{
			// Pass_Properties
			Name "Physically Based Clay"
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
			
			sampler2D _MainTex, _NormalTex, _BRDFLut; // Base texture samples
			sampler2D _DetailNormalTex; // Detailed normal texture sample
			sampler2D _layer1_RoughTex; // Layer 1 texture samples
			sampler2D _layer2_RoughTex; // Layer 2 texture samples
			float4 _MainTex_ST, _NormalTex_ST, _DetailNormalTex_ST; // Base texture scale and transform
			float4 _layer1_RoughTex_ST; // Layer 1 texture scale and transform
			float4 _layer2_RoughTex_ST; // Layer 2 texture scale and transform
			fixed4 _Color;
			half _Ambient_occlusion, _Normal_intensity, _Desaturate, _Density;
			half _DetailedNormAmount;
			half _Enable_IBL, _Flip_norm, _Flip_diffuse; // Toggles
			half _layer1_specular, _layer1_roughness, _layer1_ior; // Layer 1 properties
			half _layer2_specular, _layer2_roughness, _layer2_ior; // Layer 2 properties
			
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

			//--------------------------------------------------
			// Pixel_Shader
			half4 frag(vertex_output input) : SV_Target
			{
				// Lighting information
				UnityLight lighting;
				lighting.dir	= normalize(_WorldSpaceLightPos0.xyz);
				lighting.color	= _LightColor0.rgb * LIGHT_ATTENUATION(input);

				// Base material albedo
				material_properties base_mat;
				base_mat.albedo.rgb = tex2D(_MainTex, uv_transform(input.uv,_MainTex_ST)).rgb * _Color;
				base_mat.albedo.rgb = desaturate(base_mat.albedo, _Desaturate);
				
				// Base material normal
				half3 normal = UnpackNormal(tex2D(_NormalTex, uv_transform(input.uv, _NormalTex_ST)));
				const half3 detailed_norm_tex = UnpackNormal(tex2D(_DetailNormalTex, uv_transform(input.uv,_DetailNormalTex_ST)));

                normal = normal_map_intensity(normal, _Normal_intensity);

				// Blend between base normal and combined normals
				normal = lerp(normal, BlendNormals(normal, detailed_norm_tex), _DetailedNormAmount);

				// Flip y-axis
				normal = lerp(normal, flip_normal_y_axis(normal), _Flip_norm);

				// Create normal map
				base_mat.normal = calculate_normal_map(normal, input.tangent, input.normal);

				//--------------------------------------------------
				// Layer 1

				material_properties layer_1_mat;
				layer_1_mat.roughness	= tex2D(_layer1_RoughTex, uv_transform(input.uv,_layer1_RoughTex_ST)) * remap_roughness(_layer1_roughness);
				layer_1_mat.ior			= remap_ior(_layer1_ior);
				layer_1_mat.specular	= _layer1_specular;

				// Layer 1 View direction | Half vector | Reflection direction
				const half3 view_dir		= normalize(UnityWorldSpaceViewDir(input.world_position));
				const half3 half_vector		= normalize(view_dir + lighting.dir);
				const half3 reflection_dir	= normalize(reflect(-view_dir, base_mat.normal));
				
				layer layer_1;
				layer_1.F0		= layer_1_mat.ior;
				layer_1.n_dot_l	= saturate(dot(base_mat.normal, lighting.dir));
				layer_1.n_dot_h	= saturate(dot(base_mat.normal, half_vector));
				layer_1.n_dot_v	= saturate(dot(base_mat.normal, view_dir));
				layer_1.v_dot_h	= saturate(dot(view_dir, half_vector));

				brdf layer_1_brdf;
				layer_1_brdf.n = trowbridge_reitz_ggx(layer_1.n_dot_h, layer_1_mat.roughness);
				layer_1_brdf.g = sqr(geometry_smith(layer_1.n_dot_v, layer_1.n_dot_l, layer_1_mat.roughness));
				layer_1_brdf.f = fresnel_schlick(layer_1.v_dot_h, layer_1.F0, 1.0h);

				// Layer 1 specular
				half3 fr1 = cook_torrance_brdf(layer_1_brdf, layer_1) * layer_1_mat.specular;

				//--------------------------------------------------
				// Layer 2
				material_properties layer_2_mat;
				layer_2_mat.roughness	= tex2D(_layer2_RoughTex, uv_transform(input.uv,_layer2_RoughTex_ST)) * remap_roughness(_layer2_roughness);
				layer_2_mat.ior			= remap_ior(_layer2_ior);

				// Layer 2 Refracted View direction | Half vector | Reflection direction
				const half n = 1.0h / 1.25h;
				const half3 refract_view	= -refract(view_dir, base_mat.normal, n);
				const half3 refract_light	= -refract(lighting.dir, base_mat.normal, n);
				const half3 refract_half	= normalize(refract_view + refract_light);
				
				layer layer_2;
				layer_2.F0		= layer_2_mat.ior;
				layer_2.n_dot_l	= saturate(dot(base_mat.normal, refract_light));
				layer_2.n_dot_h	= saturate(dot(base_mat.normal, refract_half));
				layer_2.n_dot_v	= saturate(dot(base_mat.normal, refract_view));
				layer_2.v_dot_h	= saturate(dot(refract_view, refract_half));

				brdf layer_2_brdf;
				layer_2_brdf.n = trowbridge_reitz_ggx(layer_2.n_dot_h, layer_2_mat.roughness);
				layer_2_brdf.g = sqr(geometry_smith(layer_2.n_dot_v, layer_2.n_dot_l, layer_2_mat.roughness));
				layer_2_brdf.f = fresnel_schlick(layer_2.v_dot_h, layer_2.F0, 1.0h);

				// Layer 2 specular
				half3 fr2 = cook_torrance_brdf(layer_2_brdf, layer_2) * _layer2_specular; 

				//--------------------------------------------------
				// Combining both layers

				// Fresnel transmission
				const half g	= layer_1_brdf.g;
				const half3 f	= layer_1_brdf.f;
				const half3 t12 = 1.0h - f;				// Fresnel transmission from layer 1 to layer 2
				const half3 t21 = t12;					// Fresnel transmission from layer 2 to layer 1
				const half3 t	= (1.0h - g) + t21 * g;	// Internal reflection

				// Absorption term
				const half l = /*(_Density * roughTexture)*/ _Density * (1.0h / layer_2.n_dot_l + 1.0h / layer_2.n_dot_v);
				const half3 absorption = exp(-half3(0.8h, 0.8h, 0.8h) * l);

				// Ambient and Diffuse
				const half3 ambient		= calculate_ambient_light(base_mat.albedo, _Ambient_occlusion);
				const half3 orenNayar	= (1.0h - layer_2_brdf.f) * OrenNayar(base_mat.albedo, lighting, base_mat.normal, refract_view, layer_2_mat.roughness);
				const half3 lambert		= (1.0h - layer_2_brdf.f) * lambert_diffuse(base_mat.albedo, lighting.color, 1.0h);

				// Combine each layer's Specular
				const half3 fr = (fr1 + t12 * fr2 * absorption * t);

				// Composition
				const half3 outgoing_radiance = (lerp(orenNayar, lambert, _Flip_diffuse) * absorption + fr) * layer_1.n_dot_l;
				const half3 color = ambient + outgoing_radiance;

				//--------------------------------------------------
				// Layer 1 Image Based Lighting

				// Image Based Lighting - Indirect Diffuse
				const half3 indirect_diffuse = evaluate_diffuse_ibl(base_mat.normal) * base_mat.albedo;

				// Image Based Lighting - Roughness
				const half3 l1_ks_2 = fresnel_schlick_roughness(layer_1.n_dot_v, layer_1.F0, layer_1_mat.roughness);
				half3 l1_kd_2 = 1.0h - l1_ks_2;
				
				// Image Based Lighting - Indirect Specular
				Unity_GlossyEnvironmentData env_data;
				env_data.roughness = layer_1_mat.roughness;
				env_data.reflUVW = reflection_dir;
				
				const half3 fr1_env		= fresnel_schlick(layer_1.n_dot_v, layer_1.F0, 1.0h);
				const half2 brdf_lut	= tex2D(_BRDFLut, half2(layer_1.n_dot_v, layer_1_mat.roughness)).rg;
				half3 indirect_specular	= fr1_env * evaluate_specular_ibl(env_data, l1_ks_2, brdf_lut);

				// Image Based Lighting - composition
				const half3 ambient_ibl = (l1_kd_2 * indirect_diffuse + indirect_specular) * _Ambient_occlusion;
				const half3 color_ibl	= outgoing_radiance + ambient_ibl;

				// Output is changed based on if Image Based Lighting is enabled
				return half4(lerp(color, color_ibl, _Enable_IBL), 1.0h);
			}
			ENDHLSL
		}
	}
	FallBack "Legacy Shaders/Diffuse"
}