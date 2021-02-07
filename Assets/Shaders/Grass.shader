Shader "Mistwork/Grass"
{
    Properties
    {
        [Header(Colors)]
        [HDR]_MainColor("Main Color", Color) = (1, 1, 1, 1)
        _GrassTex("Grass Texture", 2D) = "white" {}
        _TerrainColor("Terrain Color", Color) = (1, 1, 1, 1)
        _TerrainTex("Terrain Texture", 2D) = "white" {}
        [HDR]_TopColor("Blade top color", Color) = (1, 1, 1, 1)
        _BottomColor("Blade bottom color", Color) = (1, 1, 1, 1)
        _RampOffset("Ramp Offset", Range(0, 1)) = 0.1
        
        [Header(Tessellation)]
        _TessellationUniform("Tessellation Uniform", Range(1, 64)) = 1

        [Header(Grass position and size)]
        _GrassHeight("Grass Height", Float) = 0
        _GrassWidth("Grass Width", Range(0.0, 2.0)) = 1.0
        _PositionRandomness("Position Randomness", Float) = 0
        _GrassNoiseTex("Random Grass height texture", 2D) = "white" {}

        [Header(Grass Blades)]
        _MaxGrassBlades("Max grass blades per triangle", Range(0, 15)) = 1
        _MinGrassBlades("Minimum grass blades per triangle", Range(0, 15)) = 1
        _MaxCameraDistance("Max camera distance", Float) = 10

        [Header(Wind Effect)]
        _WindTex("Wind texture", 2D) = "white" {}
        _WindStrength("Wind strength", Float) = 0
        _WindSpeed("Wind speed", Float) = 0

        [Header(Bend Interaction)]
        _Radius("Interaction radius", Float) = 1
        _YOffset("Height offset", Float) = 0.1
        _BendAmount("Grass bend amount", Float) = 0.2
    }

    SubShader
    {
        CGINCLUDE

            #include "UnityCG.cginc"
            #include "CustomTessellation.cginc"
            #include "Autolight.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2g 
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;  
            };

            struct g2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 col : COLOR;
                float3 normal : NORMAL;

                unityShadowCoord4 _ShadowCoord : TEXCOORD1;
                float3 viewDir : TEXCOORD2;
            };

            float4 _MainColor;
            sampler2D _GrassTex;
            float4 _GrassTex_ST;
            float4 _TerrainColor;
            sampler2D _TerrainTex;
            float4 _TerrainTex_ST;

            float _GrassHeight;
            float _GrassWidth;
            float _PositionRandomness;
            sampler2D _GrassNoiseTex;
            float4 _GrassNoiseTex_ST;

            float _MaxGrassBlades;
            float _MinGrassBlades;
            float _MaxCameraDistance;

            sampler2D _WindTex;
            float4 _WindTex_ST;
            float _WindStrength;
            float _WindSpeed;

            float _Radius;
            float _YOffset;
            float _BendAmount;

            uniform float3 _EntityPositions[100];
            uniform float _EntityPositionsSize;

            float random (float2 st) {
                return frac(sin(dot(st.xy, float2(12.9898,78.233))) * 43758.5453123);
            }

            g2f ComputeVertex(float4 pos, float2 uv, float4 col, float3 normal)
            {
                g2f o;

                o.vertex = UnityObjectToClipPos(pos);
                o.uv = uv;
                o.col = col;
                o.viewDir = WorldSpaceViewDir(pos);
                o.normal = UnityObjectToWorldNormal(normal);
                o._ShadowCoord = ComputeScreenPos(o.vertex);

                #if UNITY_PASS_SHADOWCASTER
                o.vertex = UnityApplyLinearShadowBias(o.vertex);
                #endif

                return o;
            }

            v2g vert(appdata v)
            {
                v2g o;
                o.vertex = v.vertex;
                o.uv = TRANSFORM_TEX(v.uv, _GrassTex);

                return o;
            }

            void grass_bend(inout float4 v, float4 v_world)
            {
                for (int i=0; i<_EntityPositionsSize; i++)
                {
                    float3 dis = distance(_EntityPositions[i], v_world);
                    float dis_ratio = dis / _Radius;
                    float bend_influence = 1 - saturate(dis_ratio);
                    float3 sphereDisp = v_world - _EntityPositions[i];
                    sphereDisp *= bend_influence;
                    v.xz += clamp(sphereDisp.xz * step(_YOffset, v.y), -_BendAmount, _BendAmount);
                }
            }

            [maxvertexcount(3 + 3 * 15)]
            void geom(triangle v2g input[3], inout TriangleStream<g2f> triStream)
            {
                float3 normal = normalize(cross(input[1].vertex - input[0].vertex, input[2].vertex - input[0].vertex));
                float4 world_origin_face_pos = mul(unity_ObjectToWorld, input[0].vertex);
                float distanceFromCamera = distance(_WorldSpaceCameraPos, world_origin_face_pos);
                float maxDistBasedDist = distanceFromCamera / _MaxCameraDistance;
                int grassBlades = ceil(lerp(_MaxGrassBlades, _MinGrassBlades, saturate(maxDistBasedDist)));

                float4 grassTex = tex2Dlod(_GrassTex, float4(input[2].uv, 0.0, 0.0));
                float4 terrainTex = tex2Dlod(_TerrainTex, float4(input[2].uv * _TerrainTex_ST.xy, 0.0, 0.0));

                for (uint i = 0; i < grassBlades; i++)
                {
                    float random_num1 = random(mul(unity_ObjectToWorld, input[0].vertex).xz * (i + 1));
                    float random_num2 = random(mul(unity_ObjectToWorld, input[1].vertex).xz * (i + 1));

                    float4 midpoint = (1 - sqrt(random_num1)) * input[0].vertex + (sqrt(random_num1) * (1 - random_num2)) * input[1].vertex + (sqrt(random_num1) * random_num2) * input[2].vertex;

                    random_num1 = random_num1 * 2.0 - 1.0;
                    random_num2 = random_num1 * 2.0 - 1.0;

                    float4 randomDir = normalize(input[i % 3].vertex - midpoint);

                    float4 pointA = midpoint + _GrassWidth * randomDir;
                    float4 pointB = midpoint - _GrassWidth * randomDir;

                    float4 world_midpoint = mul(unity_ObjectToWorld, midpoint);

                    float grassHeightNoise = tex2Dlod(_GrassNoiseTex, float4(world_midpoint.xz * _GrassNoiseTex_ST.xy, 0.0, 0.0)).x;
                    float heightFactor = grassHeightNoise * _GrassHeight;

                    float4 extrudedMidPoint = midpoint + float4(normal, 0.0) * heightFactor + float4(random_num1, 0.0, random_num2, 0.0) * _PositionRandomness;

                    float2 windTex = tex2Dlod(_WindTex, float4(world_midpoint.xz * _WindTex_ST.xy + _Time.y * _WindSpeed, 0.0, 0.0)).xy;
                    float2 wind = (windTex * 2.0 - 1.0) * _WindStrength;
                    extrudedMidPoint += float4(wind.x, 0.0, wind.y, 0.0);

                    grass_bend(extrudedMidPoint, world_midpoint);

                    float3 bladeNormal = normalize(cross(pointB.xyz - pointA.xyz, midpoint.xyz - extrudedMidPoint.xyz));

                    triStream.Append(ComputeVertex(pointA, float2(0,0), grassTex, normal));
                    triStream.Append(ComputeVertex(extrudedMidPoint, float2(0.5, 1), grassTex, bladeNormal));
                    triStream.Append(ComputeVertex(pointB, float2(1,0), grassTex, normal));

                    triStream.RestartStrip();
                }

                for (uint i = 0; i < 3; i++) {
                    triStream.Append(ComputeVertex(input[i].vertex, float2(0,0), terrainTex * _TerrainColor, normal));
                }

                triStream.RestartStrip();
            }

        ENDCG
        Pass
        {
            Tags { "RenderType"="Opaque" "LightMode" = "ForwardBase" }
            Cull Off

			CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment frag
            #pragma hull hull
            #pragma domain domain

            #pragma target 4.6
            #pragma multi_compile_fwdbase

            float4 _TopColor;
            float4 _BottomColor;
            float _RampOffset;

            float4 frag (g2f i) : SV_Target
            {
                float4 col = lerp(i.col * _BottomColor, _TopColor, i.uv.y * _RampOffset) * _MainColor;
                float shadow = SHADOW_ATTENUATION(i);
                col *= shadow * _MainColor;

                return col;
            }
            ENDCG
        }

        Pass 
        {
            Tags { "LightMode" = "ShadowCaster" }
            CGPROGRAM
            #pragma vertex vert
            #pragma geometry geom
            #pragma fragment fragShadow
            #pragma hull hull
            #pragma domain domain
 
            #pragma target 4.6
            #pragma multi_compile_shadowcaster

            float4 fragShadow(g2f i) : SV_Target
            {
                SHADOW_CASTER_FRAGMENT(i)
            } 
            ENDCG
        }
    }
}