uniform float Strength < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_label = "Strength"; > = 0.5;

texture2D BackBufferTex : COLOR;
sampler2D BackBuffer { Texture = BackBufferTex; };

void PostProcessVS(in uint id : SV_VertexID, out float4 position : SV_Position, out float2 texcoord : TEXCOORD)
{
	texcoord.x = (id == 2) ? 2.0 : 0.0;
	texcoord.y = (id == 1) ? 2.0 : 0.0;
	position = float4(texcoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

float4 PS_Invert(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	float4 color = tex2D(BackBuffer, uv);
	return lerp(color, 1.0 - color, Strength);
}

technique Invert
{
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Invert;
	}
}
