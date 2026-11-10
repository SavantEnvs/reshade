texture2D SrcTex : COLOR;
sampler2D Src { Texture = SrcTex; };
texture2D DstTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
storage2D Dst { Texture = DstTex; MipLevel = 0; };

groupshared float cache[64];

void CS_Main(uint3 id : SV_DispatchThreadID, uint3 tid : SV_GroupThreadID)
{
	float2 uv = (id.xy + 0.5) / float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float4 c = tex2Dlod(Src, float4(uv, 0.0, 0.0));
	cache[tid.x + tid.y * 8] = dot(c.rgb, float3(0.299, 0.587, 0.114));
	barrier();
	float l = cache[tid.x + tid.y * 8];
	tex2Dstore(Dst, int2(id.xy), float4(l, l, l, 1.0));
}

void VS(uint id : SV_VertexID, out float4 pos : SV_Position, out float2 uv : TEXCOORD)
{
	uv = float2((id << 1) & 2, id & 2);
	pos = float4(uv * 2.0 - 1.0, 0.0, 1.0);
}

float4 PS_Show(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	return tex2Dfetch(Src, int2(pos.xy));
}

technique Gray
{
	pass Compute { ComputeShader = CS_Main<8, 8>; DispatchSizeX = BUFFER_WIDTH / 8; DispatchSizeY = BUFFER_HEIGHT / 8; }
	pass Show { VertexShader = VS; PixelShader = PS_Show; }
}
