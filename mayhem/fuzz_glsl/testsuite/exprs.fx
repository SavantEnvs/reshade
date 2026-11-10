#define CAT(a, b) a##b
#define STR(x) #x
#define ADD(a, b) ((a) + (b))
#if defined(__RESHADE__) && __RESHADE__ >= 40000
	#define NEW_RESHADE 1
#elif BUFFER_WIDTH > 1920
	#define NEW_RESHADE 2
#else
	#define NEW_RESHADE 0
#endif

struct Light
{
	float3 dir;
	float3 color;
	float intensity;
};

uniform bool Enable = true;
uniform uint Count < ui_min = 1; ui_max = 8; > = 4;
uniform float3 Tint < ui_type = "color"; > = float3(1.0, 0.9, 0.8);
uniform float Time < source = "timer"; >;
uniform float4x4 Mat = float4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);

texture2D Back : COLOR;
sampler2D Samp { Texture = Back; MinFilter = POINT; };

float3 Shade(Light l, float3 n, float3 v)
{
	float3 h = normalize(l.dir + v);
	float diff = max(dot(n, l.dir), 0.0);
	float spec = pow(max(dot(n, h), 0.0), 32.0);
	return l.color * (diff + spec) * l.intensity;
}

float Fn(float x, int mode)
{
	switch (mode)
	{
		case 0: return sin(x);
		case 1: return cos(x) * 2;
		default: break;
	}
	float acc = x;
	int i = 0;
	while (i < 3) { acc = ADD(acc, i++) * 0.5; if (acc > 100.0) break; }
	do { acc -= 1.0; } while (acc > 10.0);
	return acc;
}

void VS0(uint id : SV_VertexID, out float4 pos : SV_Position, out float2 uv : TEXCOORD) { uv = float2((id << 1) & 2, id & 2); pos = float4(uv * 2.0 - 1.0, 0.0, 1.0); }

float4 PS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	Light l;
	l.dir = normalize(float3(1, 1, 1));
	l.color = Tint;
	l.intensity = Fn(Time * 0.001, (int)Count % 3);
	float3 c = tex2D(Samp, uv).rgb;
	float2x2 m = float2x2(0.5, 0.25, 0.25, 0.5);
	float2 r = mul(m, uv);
	uint bits = asuint(c.r) ^ (1u << 3);
	c += Shade(l, float3(0, 0, 1), float3(r, 1.0)) * (Enable ? 1.0 : 0.0);
	c = c.bgr + float3(r.xy, (float)(bits & 0xFFu) / 255.0);
	return float4(saturate(c), 1.0);
}

technique Exprs { pass { VertexShader = VS0; PixelShader = PS; } }
