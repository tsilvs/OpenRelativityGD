// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'
// Upgrade NOTE: replaced '_World2Object' with 'unity_WorldToObject'

Shader "Relativity/ColorOnly" 
{
	Properties
	{
		_MainTex("Base (RGB)", 2D) = "" {} //Visible Spectrum Texture ( RGB )
		_UVTex("UV",2D) = "" {} //UV texture
		_IRTex("IR",2D) = "" {} //IR texture
		_piw("piw", Vector) = (0,0,0,0) //Vector that represents object's position in world frame
		_viw("viw", Vector) = (0,0,0,0) //Vector that represents object's velocity in world frame
		_aviw("aviw", Vector) = (0,0,0,0) //Vector that represents object's angular velocity times the object's world scale
		//_gtt("gtt", float) = 0 //float that represents 00 component of metric due to player acceleration
		_strtTime("strtTime", float) = 0 //For moving objects, when they created, this variable is set to current world time
		_Cutoff("Base Alpha cutoff", Range(0,.9)) = 0.1 //Used to determine when not to render alpha materials
	}

		CGINCLUDE

#pragma exclude_renderers xbox360
#pragma glsl
#include "UnityCG.cginc"

			//Color shift variables, used to make guassians for XYZ curves
#define xla 0.39952807612909519
#define xlb 444.63156780935032
#define xlc 20.095464678736523

#define xha 1.1305579611401821
#define xhb 593.23109262398259
#define xhc 34.446036241271742

#define ya 1.0098874822455657
#define yb 556.03724875218927
#define yc 46.184868454550838

#define za 2.0648400466720593
#define zb 448.45126344558236
#define zc 22.357297606503543

//Used to determine where to center UV/IR curves
#define IR_RANGE 400
#define IR_START 700
#define UV_RANGE 380
#define UV_START 0

//Quaternion math
#define quaternion float4
#define PI_F 3.14159265f

//Prevent NaN and Inf
#define divByZeroCutoff 1e-8f

//This is the data sent from the vertex shader to the fragment shader
struct v2f
		{
			float4 pos : POSITION; //internal, used for display
			float4 pos2 : TEXCOORD0; //Position in world, relative to player position in world
			float2 uv1 : TEXCOORD1; //Used to specify what part of the texture to grab in the fragment shader(not relativity specific, general shader variable)
			float svc : TEXCOORD2; //sqrt( 1 - (v-c)^2), calculated in vertex shader to save operations in fragment. It's a term used often in lorenz and doppler shift calculations, so we need to keep it cached to save computing
			float4 vr : TEXCOORD3; //Relative velocity of object vpc - viw
		};


		//Variables that we use to access texture data
		sampler2D _MainTex;
		sampler2D _IRTex;
		sampler2D _UVTex;
		sampler2D _CameraDepthTexture;

		float4 _piw = float4(0, 0, 0, 0); //position of object in world
		float4 _viw = float4(0, 0, 0, 0); //velocity of object in world
		float4 _aviw = float4(0, 0, 0, 0); //scaled angular velocity
		float4 _vpc = float4(0, 0, 0, 0); //velocity of player
		//float _gtt = 1; //velocity of player
		float4 _playerOffset = float4(0, 0, 0, 0); //player position in world
		float _spdOfLight = 100; //current speed of light
		float _wrldTime = 0; //current time in world
		float _strtTime = 0; //starting time in world
		float _colorShift = 1; //actually a boolean, should use color effects or not ( doppler + spotlight). 

		float xyr = 1; // xy ratio
		float xs = 1; // x scale

		uniform float4 _MainTex_TexelSize;
		uniform float4 _CameraDepthTexture_ST;

		//Per vertex operations
		v2f vert(appdata_img v)
		{
			v2f o;

			float4 viw = _viw;

			o.uv1.xy = v.texcoord; //get the UV coordinate for the current vertex, will be passed to fragment shade

			float speed = sqrt(dot(_vpc, _vpc));
			//vw + vp/(1+vw*vp/c^2)

			float vuDot = dot(_vpc, viw); //Get player velocity dotted with velocity of the object.
			float4 vr;
			//IF our speed is zero, this parallel velocity component will be NaN, so we have a check here just to be safe
			if (speed > divByZeroCutoff)
			{
				float4 uparra = (vuDot / (speed*speed)) * _vpc; //Get the parallel component of the object's velocity
				//Get the perpendicular component of our velocity, just by subtraction
				float4 uperp = viw - uparra;
				//relative velocity calculation
				vr = (_vpc - uparra - (sqrt(1 - speed*speed))*uperp) / (1 + vuDot);
			}
			//If our speed is nearly zero, it could lead to infinities.
			else
			{
				//relative velocity calculation
				vr = -viw;
			}

			//set our relative velocity
			o.vr = vr;
			vr *= -1;
			//relative speed
			float speedr = sqrt(dot(vr, vr));
			o.svc = sqrt(1 - speedr * speedr); // To decrease number of operations in fragment shader, we're storing this value

			//You need this otherwise the screen flips and weird stuff happens
#ifdef SHADER_API_D3D9
			if (_MainTex_TexelSize.y < 0)
				o.uv1.y = 1.0 - o.uv1.y;
#endif 

			//For a color only shader, we don't relativistically transform the position
			o.pos = UnityObjectToClipPos(v.vertex);
			o.pos2 = v.vertex - _playerOffset;

			return o;
		}

		//Color functions, there's no check for division by 0 which may cause issues on
		//some graphics cards.
		float3 RGBToXYZC(float3 rgb)
		{
			float3 xyz;
			xyz.x = dot(float3(0.13514, 0.120432, 0.057128), rgb);
			xyz.y = dot(float3(0.0668999, 0.232706, 0.0293946), rgb);
			xyz.z = dot(float3(0.0, 0.0000218959, 0.358278), rgb);
			return xyz;
		}
		float3 XYZToRGBC(float3 xyz)
		{
			float3 rgb;
			rgb.x = dot(float3(9.94845, -5.1485, -1.16389), xyz);
			rgb.y = dot(float3(-2.86007, 5.77745, -0.0179627), xyz);
			rgb.z = dot(float3(0.000174791, -0.000353084, 2.79113), xyz);
			return rgb;
		}
		float3 weightFromXYZCurves(float3 xyz)
		{
			float3 returnVal;
			returnVal.x = dot(float3(0.0735806, -0.0380793, -0.00860837), xyz);
			returnVal.y = dot(float3(-0.0665378, 0.134408, -0.000417865), xyz);
			returnVal.z = dot(float3(0.00000299624, -0.00000605249, 0.0484424), xyz);
			return returnVal;
		}

		float getXFromCurve(float3 param, float shift)
		{
			//Use constant memory, or let the compiler optimize constants, where we can get away with it:
			const float sqrt2Pi = sqrt(2 * 3.14159265358979323f);

			//Re-use memory to save per-vertex operations:
			float bottom2 = param.z * shift;
			bottom2 *= bottom2;

			float top1 = param.x * xla * exp(-((((param.y * shift) - xlb) * ((param.y * shift) - xlb))
				/ (2 * (bottom2 + (xlc * xlc))))) * sqrt2Pi;
			float bottom1 = sqrt(1 / bottom2 + 1 / (xlc * xlc));

			float top2 = param.x * xha * exp(-((((param.y * shift) - xhb) * ((param.y * shift) - xhb))
				/ (2 * (bottom2 + (xhc * xhc))))) * sqrt2Pi;
			bottom2 = sqrt(1 / bottom2 + 1 / (xhc * xhc));

			return (top1 / bottom1) + (top2 / bottom2);
		}
		float getYFromCurve(float3 param, float shift)
		{
			//Use constant memory, or let the compiler optimize constants, where we can get away with it:
			const float sqrt2Pi = sqrt(2 * 3.14159265358979323f);

			//Re-use memory to save per-vertex operations:
			float bottom = param.z * shift;
			bottom *= bottom;

			float top = param.x * ya * exp(-((((param.y * shift) - yb) * ((param.y * shift) - yb))
				/ (2 * (bottom + yc * yc)))) * sqrt2Pi;
			bottom = sqrt(1 / bottom + 1 / (yc * yc));

			return top / bottom;
		}

		float getZFromCurve(float3 param, float shift)
		{
			//Use constant memory, or let the compiler optimize constants, where we can get away with it:
			const float sqrt2Pi = sqrt(2 * 3.14159265358979323f);

			//Re-use memory to save per-vertex operations:
			float bottom = param.z * shift;
			bottom *= bottom;

			float top = param.x * za * exp(-((((param.y * shift) - zb) * ((param.y * shift) - zb))
				/ (2 * (bottom + zc * zc))))* sqrt2Pi;
			bottom = sqrt(1 / bottom + 1 / (zc * zc));

			return top / bottom;
		}

		float3 constrainRGB(float r, float g, float b)
		{
			float w;

			w = (0 < r) ? 0 : r;
			w = (w < g) ? w : g;
			w = (w < b) ? w : b;
			w = -w;

			if (w > 0) {
				r += w;  g += w; b += w;
			}
			w = r;
			w = (w < g) ? g : w;
			w = (w < b) ? b : w;

			if (w > 1)
			{
				r /= w;
				g /= w;
				b /= w;
			}
			float3 rgb;
			rgb.x = r;
			rgb.y = g;
			rgb.z = b;
			return rgb;

		};

		//Per pixel shader, does color modifications
		float4 frag(v2f i) : COLOR
		{
			//Used to maintian a square scale ( adjust for screen aspect ratio )
			float3 x1y1z1 = i.pos2 * (float3)(2 * xs, 2 * xs / xyr, 1);

			// ( 1 - (v/c)cos(theta) ) / sqrt ( 1 - (v/c)^2 )
			float shift = (1 - dot(x1y1z1, i.vr.xyz) / sqrt(dot(x1y1z1, x1y1z1))) / i.svc;
			if (_colorShift == 0)
			{
				shift = 1.0f;
			}

			//This is a debatable and stylistic point,
			// but, if we think of the albedo as due to (diffuse) reflectance, we should do this:
			shift *= shift;
			// Reflectance squares the effective Doppler shift. Unsquared, the shift
			// would be appropriate for a black body or spectral emission spectrum.
			// The factor can thought of as due to the apparent velocity of a (static with respect to world coordinates) source image,
			// which is twice as much as the velocity of the (diffuse) "mirror." (See: https://arxiv.org/pdf/physics/0605100.pdf )
			// The point is, most of the colors of common objects that humans see are due to reflectance.
			// Light directly from a light bulb, or flame, or LED, would not receive this Doppler factor squaring.

			//Get initial color 
			float4 data = tex2D(_MainTex, i.uv1).rgba;
			float UV = tex2D(_UVTex, i.uv1).r;
			float IR = tex2D(_IRTex, i.uv1).r;

			//Set alpha of drawing pixel to 0 if vertex shader has determined it should not be drawn.
			//data.a = i.draw ? data.a : 0;

			float3 rgb = data.xyz;

			//Color shift due to doppler, go from RGB -> XYZ, shift, then back to RGB.
			float3 xyz = RGBToXYZC(rgb);
			float3 weights = weightFromXYZCurves(xyz);
			float3 rParam,gParam,bParam,UVParam,IRParam;
			rParam.x = weights.x; rParam.y = (float)615; rParam.z = (float)8;
			gParam.x = weights.y; gParam.y = (float)550; gParam.z = (float)4;
			bParam.x = weights.z; bParam.y = (float)463; bParam.z = (float)5;
			UVParam.x = 0.02; UVParam.y = UV_START + UV_RANGE*UV; UVParam.z = (float)5;
			IRParam.x = 0.02; IRParam.y = IR_START + IR_RANGE*IR; IRParam.z = (float)5;

			xyz.x = (getXFromCurve(rParam, shift) + getXFromCurve(gParam,shift) + getXFromCurve(bParam,shift) + getXFromCurve(IRParam,shift) + getXFromCurve(UVParam,shift));
			xyz.y = (getYFromCurve(rParam, shift) + getYFromCurve(gParam,shift) + getYFromCurve(bParam,shift) + getYFromCurve(IRParam,shift) + getYFromCurve(UVParam,shift));
			xyz.z = (getZFromCurve(rParam, shift) + getZFromCurve(gParam,shift) + getZFromCurve(bParam,shift) + getZFromCurve(IRParam,shift) + getZFromCurve(UVParam,shift));
			float3 rgbFinal = XYZToRGBC(pow(1 / shift ,3) * xyz);
			rgbFinal = constrainRGB(rgbFinal.x,rgbFinal.y, rgbFinal.z); //might not be needed

																		//Test if unity_Scale is correct, unity occasionally does not give us the correct scale and you will see strange things in vertices,  this is just easy way to test
																		//float4x4 temp  = mul(unity_Scale.w*_Object2World, _World2Object);
																		//float4 temp2 = mul( temp,float4( (float)rgbFinal.x,(float)rgbFinal.y,(float)rgbFinal.z,data.a));
																		//return temp2;	
																		//float4 temp2 =float4( (float)rgbFinal.x,(float)rgbFinal.y,(float)rgbFinal.z,data.a );
			return float4(rgbFinal.xyz,data.a); //use me for any real build
		}

		ENDCG

		Subshader {

		Pass{
			//Shader properties, for things such as transparency
			Cull Off ZWrite On
			ZTest LEqual
			Fog{ Mode off } //Fog does not shift properly and there is no way to do so with this fog
			Tags{ "RenderType" = "Transparent" "Queue" = "Transparent" }

			AlphaTest Greater[_Cutoff]
			Blend SrcAlpha OneMinusSrcAlpha

			CGPROGRAM

			#pragma fragmentoption ARB_precision_hint_nicest

			#pragma vertex vert
			#pragma fragment frag
			#pragma target 3.0

			ENDCG
		}
	}

	Fallback "Unlit/Transparent"
}

