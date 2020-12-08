TEXTURE2D(_CameraDepthTexture);
SAMPLER(sampler_CameraDepthTexture);

TEXTURE2D(_CameraDepthNormalsTexture);
SAMPLER(sampler_CameraDepthNormalsTexture);
float4 _CameraDepthNormalsTexture_TexelSize;

TEXTURE2D(_CameraColorTexture);
SAMPLER(sampler_CameraColorTexture);

float3 DecodeNormal(float4 enc)
{
    float kScale = 1.7777;
    float3 nn = enc.xyz*float3(2*kScale,2*kScale,0) + float3(-kScale,-kScale,1);
    float g = 2.0 / dot(nn.xyz,nn.xyz);
    float3 n;
    n.xy = g*nn.xy;
    n.z = g-1;
    return n;
} 

void Outlines_float(float3 WorldPosition, float2 ScreenPosition, float2 UV, float3 Color, float OutlineThickness, float3 OutlineColor, float OutlineDepthMultiplier, float OutlineDepthBias, float OutlineNormalMultiplier, float OutlineNormalBias, 
    out float Depth, out float3 Normal, out float DepthOutline, out float NormalOutline, out float Outline, out float3 MainLightShadow, out float3 Detail, out float3 Composite)
{
    // sample distance
    float halfScaleFloor = floor(OutlineThickness * 0.5);
    float halfScaleCeil = ceil(OutlineThickness * 0.5);
    float2 Texel = (1.0) / float2(_CameraDepthNormalsTexture_TexelSize.z, _CameraDepthNormalsTexture_TexelSize.w);
    
    // offset sample positions
    float2 uvSamples[4];
    uvSamples[0] = UV - float2(Texel.x, Texel.y) * halfScaleFloor;
    uvSamples[1] = UV + float2(Texel.x, Texel.y) * halfScaleCeil;
    uvSamples[2] = UV + float2(Texel.x * halfScaleCeil, -Texel.y * halfScaleFloor);
    uvSamples[3] = UV + float2(-Texel.x * halfScaleFloor, Texel.y * halfScaleCeil);

    // base (center) values
    Depth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, UV).r;
    Normal = DecodeNormal(SAMPLE_TEXTURE2D(_CameraDepthNormalsTexture, sampler_CameraDepthNormalsTexture, UV));
    Detail = SAMPLE_TEXTURE2D(_CameraColorTexture, sampler_CameraColorTexture, UV); // r alpha map for detail, b SSAO

    float depthDifference = 0;
    float normalDifference = 0;
    float shadowDistance = 0;
    float detailDifference0 = 0;

    MainLightShadow = 0;

    #ifndef SHADERGRAPH_PREVIEW
        half4 m_shadowCoord = TransformWorldToShadowCoord(WorldPosition);
        ShadowSamplingData m_shadowSamplingData = GetMainLightShadowSamplingData();
        half shadowStrength = GetMainLightShadowStrength();
        MainLightShadow = SampleShadowmap(m_shadowCoord, TEXTURE2D_ARGS(_MainLightShadowmapTexture, sampler_MainLightShadowmapTexture), m_shadowSamplingData, shadowStrength, false);
        //MainLightShadow = 1 - MainLightShadow; 
    #endif

    for(int i = 0; i < 4 ; i++)
    {
        // depth
        depthDifference = depthDifference + Depth - SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, uvSamples[i]).r;

        // normals
        float3 normalDelta = Normal - DecodeNormal(SAMPLE_TEXTURE2D(_CameraDepthNormalsTexture, sampler_CameraDepthNormalsTexture, uvSamples[i]));
        normalDelta = normalDelta.r + normalDelta.g + normalDelta.b;
        normalDifference = normalDifference + normalDelta;
    
        // detail from opaque pass
        detailDifference0 = detailDifference0 + Detail.r - SAMPLE_TEXTURE2D(_CameraColorTexture, sampler_CameraColorTexture, uvSamples[i]).r;
    }

    // depth sensitivity
    depthDifference = depthDifference * OutlineDepthMultiplier;
    depthDifference = saturate(depthDifference);
    depthDifference = pow(depthDifference, OutlineDepthBias);
    DepthOutline = depthDifference;

    // normal sensitivity
    normalDifference = normalDifference * OutlineNormalMultiplier;
    normalDifference = saturate(normalDifference);
    normalDifference = pow(normalDifference, OutlineNormalBias);
    NormalOutline = normalDifference;

    // combine outlines
    Outline = max(max(DepthOutline, NormalOutline), detailDifference0);

    // Combine combine outlines with toon lighting and AO
    Composite = lerp(Color.rgb, OutlineColor, Outline) * MainLightShadow * (1 - Detail.g);

    //Outline = SSAO;

}