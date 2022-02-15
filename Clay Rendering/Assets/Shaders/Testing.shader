Shader "Custom/Testing"
{
	//--------------------------------------------------
	// A shader for testing functions
	Properties
    {
	    [Header(Textures)]
    	[Space(10)]
        [MainTexture] _MainTex	("Albedo (RGB)", 2D) = "white" {}
    	
	    [Header(PBR properties)]
    	[Space(10)]
    	[MainColor] _Color	("Color / Tint", Color) = (1,1,1,1)
    	_Roughness ("Roughness", Range(0, 1)) = 1.0
    	_Amount ("Lerp amount", Range(0, 1)) = 0
    	_Compare ("Show different oren", Range(0, 1)) = 0
    	_saturation ("satuation", Range(0, 1)) = 0
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

			// Pixel Shader variables
			sampler2D _MainTex;
			float4 _MainTex_ST;
			float4 _Color;
			float _Roughness, _Amount, _Compare, _saturation;

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
			float4 frag(vertex_output input) : SV_Target
			{
				// Lighting information
				UnityLight lighting;
				lighting.dir = normalize(lerp(_WorldSpaceLightPos0.xyz, _WorldSpaceLightPos0.xyz - input.world_position.xyz, _WorldSpaceLightPos0.w));
				lighting.color = _LightColor0.rgb * LIGHT_ATTENUATION(input);
				lighting.ndotl = -1.0h;
				
				// View direction | half vector | reflection direction
				const half3 view_dir = normalize(UnityWorldSpaceViewDir(input.world_position));
				const half3 half_vector = normalize(view_dir + lighting.dir);
				const half3 reflection_dir = normalize(reflect(-view_dir, input.normal));
			
				const float n_dot_l = saturate(dot(input.normal, lighting.dir));
				const float n_dot_v = saturate(dot(input.normal, view_dir));
				
				half3 albedo = tex2D(_MainTex, uv_transform(input.uv, _MainTex_ST)) * _Color;
				albedo = desaturate(albedo, _saturation);
				
				float3 oren_nayar1 = OrenNayar(albedo, lighting, input.normal, view_dir, _Roughness);
				float3 oren_nayar2 = Oren_nayar(albedo, n_dot_l, n_dot_v, _Roughness, lighting.color);
				float3 oren_nayar = lerp(oren_nayar1, oren_nayar2, _Compare);
				float3 lambert = lambert_diffuse(albedo, lighting.color, 1.0f) * saturate(dot(input.normal, lighting.dir));
				float3 half_l = half_lambert(albedo, n_dot_l, lighting.color);
				
				return float4(lerp(oren_nayar, lambert, _Amount), 1.0f);
			}
			ENDHLSL
		}
    	Pass
    	{
    		Tags { "Lightmode" = "ShadowCaster" }
    		
    		HLSLPROGRAM
			#pragma vertex vert
    		#pragma fragment frag
    		#pragma multi_compile_shadowcaster

    		#include "UnityCG.cginc"

    		struct v2f
			{
				V2F_SHADOW_CASTER;
			};

    		v2f vert(appdata_base v)
    		{
    			v2f o;
    			TRANSFER_SHADOW_CASTER_NORMALOFFSET(o);
    			return o;
    		}

    		float4 frag(v2f i) : SV_Target
    		{
				SHADOW_CASTER_FRAGMENT(i);
    		}
    		ENDHLSL
        }
    }
    FallBack "Legacy Shaders/Diffuse"
}