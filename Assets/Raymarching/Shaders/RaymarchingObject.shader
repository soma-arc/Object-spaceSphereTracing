﻿Shader "Raymarching/Object"
{

SubShader
{

Tags { "RenderType" = "Opaque" "DisableBatching" = "True" }

CGINCLUDE

#include "UnityCG.cginc"
#include "Lighting.cginc"
#include "Utils.cginc"
#include "Primitives.cginc"

#define PI 3.14159265358979

float DistanceFunction(float3 pos)
{
	float t = _Time.x;
	float a = 6 * PI * t;
	float s = pow(sin(a), 2.0);
	float d1 = sphere(pos, 0.75);
	float d2 = roundBox(
		repeat(pos, 0.2),
		0.1 - 0.1 * s,
		0.1 / length(pos * 2.0));
	return lerp(d1, d2, s);
}

#include "Raymarching.cginc"

inline bool IsInnerBox(float3 pos, float3 scale)
{
	return all(max(scale * 0.5 - abs(pos), 0.0));
}

inline bool IsInnerSphere(float3 pos, float3 scale)
{
	return length(pos) < abs(scale) * 0.5;
}

void Raymarch(inout float3 pos, out float distance, float3 rayDir, float minDistance, int loop)
{
	float len = 0.0;

	for (int n = 0; n < loop; ++n) {
		distance = ObjectSpaceDistanceFunction(pos);
		len += distance;
		pos += rayDir * distance;
		if (!IsInnerBox(ToLocal(pos), _Scale) || distance < minDistance) break;
	}

	if (distance > minDistance) discard;
}

GBufferOut frag(VertObjectOutput i)
{
	float3 rayDir = GetRayDirection(i.screenPos);
	float3 pos = i.worldPos;
	float distance = 0;
	Raymarch(pos, distance, rayDir, 0.001, 30);

	float depth = GetDepth(pos);
	float3 normal = i.worldNormal * 0.5 + 0.5;
	if (distance > 0.0) {
		normal = GetNormalOfObjectSpaceDistanceFunction(pos);
	}

	GBufferOut o;
	o.diffuse = float4(1.0, 1.0, 1.0, 1.0);
	o.specular = float4(0.5, 0.5, 0.5, 1.0);
	o.emission = 0.0f;
	o.normal = float4(normal, 1.0);
	o.depth = depth;

#ifndef UNITY_HDR_ON
	o.emission.rgb = exp2(-o.emission.rgb);
#endif

	return o;
}

#ifdef SHADOWS_CUBE

float4 frag_shadow(VertShadowOutput i) : SV_Target
{
	float3 rayDir = GetRayDirectionForShadow(i.screenPos);
	float3 pos = i.worldPos;
	float distance = 0.0;
	Raymarch(pos, distance, rayDir, 0.001, 10);

	i.vec = pos - _LightPositionRange.xyz;
	SHADOW_CASTER_FRAGMENT(i);
}

#else

void frag_shadow(
	VertShadowOutput i, 
	out float4 outColor : SV_Target, 
	out float  outDepth : SV_Depth)
{
	// light direction of directional light 
	float3 rayDir = -UNITY_MATRIX_V[2].xyz;

	// light direction of spot light
	if ((UNITY_MATRIX_P[3].x != 0.0) || 
		(UNITY_MATRIX_P[3].y != 0.0) || 
		(UNITY_MATRIX_P[3].z != 0.0)) {
		rayDir = GetRayDirectionForShadow(i.screenPos);
	}

	float3 pos = i.worldPos;
	float distance = 0.0;
	Raymarch(pos, distance, rayDir, 0.001, 10);

	float4 opos = mul(unity_WorldToObject, float4(pos, 1.0));
	opos = UnityClipSpaceShadowCasterPos(opos, i.normal);
	opos = UnityApplyLinearShadowBias(opos);

	outColor = outDepth = opos.z / opos.w;
}

#endif

ENDCG

Pass
{
	Tags { "LightMode" = "Deferred" }

	Stencil
	{
		Comp Always
		Pass Replace
		Ref 128
	}

	CGPROGRAM
	#pragma target 3.0
	#pragma multi_compile ___ UNITY_HDR_ON
	#pragma vertex vert_object
	#pragma fragment frag
	ENDCG
}

Pass
{
	Tags { "LightMode" = "ShadowCaster" }

	CGPROGRAM
	#pragma target 3.0
	#pragma vertex vert_shadow
	#pragma fragment frag_shadow
	#pragma multi_compile_shadowcaster
	#pragma fragmentoption ARB_precision_hint_fastest
	ENDCG
}

}

Fallback Off

}