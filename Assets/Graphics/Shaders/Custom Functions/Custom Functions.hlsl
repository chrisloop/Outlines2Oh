TEXTURE2D(_CameraDepthTexture);
SAMPLER(sampler_CameraDepthTexture);

TEXTURE2D(_CameraDepthNormalsTexture);
SAMPLER(sampler_CameraDepthNormalsTexture);
float4 _CameraDepthNormalsTexture_TexelSize;

TEXTURE2D(_CameraColorTexture);
SAMPLER(sampler_CameraColorTexture);
float4 _CameraColorTexture_TexelSize;

//
// Painterly
//
void Painterly_float(float2 UV, float _Radius, out float3 Out)
{
    Out = 0;

    #ifndef SHADERGRAPH_PREVIEW

    float3 mean[4] = {
        {0, 0, 0},
        {0, 0, 0},
        {0, 0, 0},
        {0, 0, 0}
    };

    float3 sigma[4] = {
        {0, 0, 0},
        {0, 0, 0},
        {0, 0, 0},
        {0, 0, 0}
    };

    float2 start[4] = {{-_Radius, -_Radius}, {-_Radius, 0}, {0, -_Radius}, {0, 0}};

    float2 pos;
    float3 col;
    for (int k = 0; k < 4; k++) {
        for(int i = 0; i <= _Radius; i++) {
            for(int j = 0; j <= _Radius; j++) {
                pos = float2(i, j) + start[k];

                col = SAMPLE_TEXTURE2D(_CameraColorTexture, sampler_CameraColorTexture, float4(UV + float2(pos.x * _CameraColorTexture_TexelSize.x, pos.y * _CameraColorTexture_TexelSize.y), 0., 0.)).rgb;
                mean[k] += col; 
                sigma[k] += col * col;
            }
        }
    }

    float sigma2;

    float n = pow(_Radius + 1, 2);
    float4 color = SAMPLE_TEXTURE2D(_CameraColorTexture, sampler_CameraColorTexture, UV);
    float min = 1;

    for (int l = 0; l < 4; l++) {
        mean[l] /= n;
        sigma[l] = abs(sigma[l] / n - mean[l] * mean[l]);
        sigma2 = sigma[l].r + sigma[l].g + sigma[l].b;

        if (sigma2 < min) {
            min = sigma2;
            color.rgb = mean[l].rgb;
        }
    }

    Out = color;

    #endif
}

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

void Outlines_float(float3 WorldPosition, float2 ScreenPosition, float2 UV, float3 Color, float OutlineThickness, float3 OutlineColor, float OutlineDepthMultiplier, float OutlineDepthBias, float OutlineNormalMultiplier, float OutlineNormalBias, float PainterlyRadius, float PainterlyStrength,
    out float Depth, out float3 Normal, out float DepthOutline, out float NormalOutline, out float Outline, out float3 MainLightShadow, out float3 Detail, out float3 OriginalColor, out float3 Composite)
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

    // painterly detail
    float3 PainterlyDetail = 1;

    if (PainterlyRadius > 0)
    {
        Painterly_float(UV, PainterlyRadius, PainterlyDetail);

        PainterlyDetail = clamp(PainterlyDetail + (1 - PainterlyStrength), 0, 1);
    }
    // Combine combine base color, outlines, Shadow map, Ambient Occlusion and Painterly Tint
    Composite = lerp(Color.rgb, OutlineColor, Outline) * MainLightShadow * (1 - Detail.g) * PainterlyDetail.r;

    OriginalColor = PainterlyDetail;
}

