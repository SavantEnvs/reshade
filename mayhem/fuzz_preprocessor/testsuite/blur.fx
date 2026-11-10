#ifndef BLUR_RADIUS
	#define BLUR_RADIUS 4
#endif
#define SQR(x) ((x) * (x))

namespace Blur
{
	uniform int Quality <
		ui_type = "combo";
		ui_items = "Low\0Medium\0High\0";
		ui_tooltip = "Selects the blur quality.";
	> = 1;
	uniform float2 PixelSize < source = "pingpong"; min = 0.0; max = 1.0; step = 0.1; > = float2(1.0, 1.0);

	texture2D ColorTex : COLOR;
	texture2D HalfTex { Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F; MipLevels = 2; };
	sampler2D Color { Texture = ColorTex; AddressU = CLAMP; AddressV = CLAMP; MagFilter = LINEAR; MinFilter = LINEAR; };
	sampler2D Half { Texture = HalfTex; };

	struct VSOut
	{
		float4 position : SV_Position;
		float2 uv : TEXCOORD0;
	};

	VSOut VS(uint id : SV_VertexID)
	{
		VSOut o;
		o.uv = float2((id << 1) & 2, id & 2);
		o.position = float4(o.uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
		return o;
	}

	static const float weights[3] = { 0.25, 0.5, 0.25 };

	float4 Gather(sampler2D s, float2 uv, float2 dir)
	{
		float4 sum = 0.0;
		float total = 0.0;
		[unroll]
		for (int i = -BLUR_RADIUS; i <= BLUR_RADIUS; ++i)
		{
			float w = exp(-SQR(float(i)) / 8.0);
			sum += tex2Dlod(s, float4(uv + dir * i * PixelSize, 0, 0)) * w;
			total += w;
		}
		return sum / total;
	}

	float4 PS_Down(VSOut i) : SV_Target { return Gather(Color, i.uv, float2(1.0, 0.0)); }
	float4 PS_Up(VSOut i) : SV_Target
	{
		float4 c = Gather(Half, i.uv, float2(0.0, 1.0));
		if (Quality == 0)
			return c;
		else if (Quality == 1)
			return saturate(c * 1.1);
		return pow(abs(c), 0.9) * weights[1];
	}
}

technique Blur < ui_label = "Blur"; >
{
	pass Down { VertexShader = Blur::VS; PixelShader = Blur::PS_Down; RenderTarget = Blur::HalfTex; }
	pass Up { VertexShader = Blur::VS; PixelShader = Blur::PS_Up; SRGBWriteEnable = true; }
}
