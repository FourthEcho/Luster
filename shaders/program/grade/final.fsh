/*
====================================================================================================

    Copyright (C) 2026 FourthEcho

    All Rights Reserved unless otherwise explicitly stated.


    By downloading this you have agreed to the license and terms of use.
    These can be found inside the included license-file.

    Violating these terms may be penalized with actions according to the Digital Millennium
    Copyright Act (DMCA), the Information Society Directive and/or similar laws
    depending on your country.

====================================================================================================
*/

#include "/lib/global.glsl"

layout(location = 0) out vec3 fragmentColor;

in vec2 uv;

// ------------
//   Uniforms
// ------------

uniform sampler2D colortex0; // Scene color

#if debugView == debugViewSampler
uniform sampler2D debugSampler;
#endif

uniform float viewHeight;
uniform float viewWidth;
uniform float frameTimeCounter;

#include "/lib/util/bicubic.glsl"
#include "/lib/util/color.glsl"
#include "/lib/util/random.glsl"
/*
--------------------------------------------------------------------------------

  GLSL Debug Text Renderer by SixthSurge (updated 2023-04-08)

  Character set based on Monocraft by IdreesInc
  https://github.com/IdreesInc/Monocraft

  With additional characters added by WoMspace

  Usage:

  // Call beginText to initialize the text renderer. You can scale the fragment
position to adjust the size of the text beginText(ivec2(gl_FragCoord.xy),
ivec2(0, viewHeight)); ^ fragment position     ^ text box position (upper left
corner)

  // You can print various data types
  printBool(false);
  printFloat(sqrt(-1.0)); // Prints "NaN"
  printInt(42);
  printVec3(skyColor);

  // ...or arbitrarily long strings
  print((_H, _e, _l, _l, _o, _comma, _space, _w, _o, _r, _l, _d));

  // To start a new line, use
  printLine();

  // You can also configure the text color on the fly
  text.fgCol = vec4(1.0, 0.0, 0.0, 1.0);
  text.bgCol = vec4(0.0, 0.0, 0.0, 1.0);

  // ...as well as the number base and number of decimal places to print
  text.base = 16;
  text.fpPrecision = 4;

  // Finally, call endText to blend the current fragment color with the text
  endText(sceneColor);

  Important: any variables you display must be the same for all fragments, or
  at least all of the fragments that the text covers. Otherwise, different
  fragments will try to print different values, resulting in, well, a mess

--------------------------------------------------------------------------------
*/

#if !defined INCLUDE_UTILITY_TEXT_RENDERING
#define INCLUDE_UTILITY_TEXT_RENDERING

// Characters

const uint _A = 0x747f18c4u;
const uint _B = 0xf47d18f8u;
const uint _C = 0x746108b8u;
const uint _D = 0xf46318f8u;
const uint _E = 0xfc39087cu;
const uint _F = 0xfc390840u;
const uint _G = 0x7c2718b8u;
const uint _H = 0x8c7f18c4u;
const uint _I = 0x71084238u;
const uint _J = 0x084218b8u;
const uint _K = 0x8cb928c4u;
const uint _L = 0x8421087cu;
const uint _M = 0x8eeb18c4u;
const uint _N = 0x8e6b38c4u;
const uint _O = 0x746318b8u;
const uint _P = 0xf47d0840u;
const uint _Q = 0x74631934u;
const uint _R = 0xf47d18c4u;
const uint _S = 0x7c1c18b8u;
const uint _T = 0xf9084210u;
const uint _U = 0x8c6318b8u;
const uint _V = 0x8c62a510u;
const uint _W = 0x8c635dc4u;
const uint _X = 0x8a88a8c4u;
const uint _Y = 0x8a884210u;
const uint _Z = 0xf844447cu;
const uint _a = 0x0382f8bcu;
const uint _b = 0x85b318f8u;
const uint _c = 0x03a308b8u;
const uint _d = 0x0b6718bcu;
const uint _e = 0x03a3f83cu;
const uint _f = 0x323c8420u;
const uint _g = 0x03e2f0f8u;
const uint _h = 0x842d98c4u;
const uint _i = 0x40308418u;
const uint _j = 0x080218b8u;
const uint _k = 0x4254c524u;
const uint _l = 0x6108420cu;
const uint _m = 0x06ab5ac4u;
const uint _n = 0x07a318c4u;
const uint _o = 0x03a318b8u;
const uint _p = 0x05b31f40u;
const uint _q = 0x03671784u;
const uint _r = 0x05b30840u;
const uint _s = 0x03e0e0f8u;
const uint _t = 0x211c420cu;
const uint _u = 0x046318bcu;
const uint _v = 0x04631510u;
const uint _w = 0x04635abcu;
const uint _x = 0x04544544u;
const uint _y = 0x0462f0f8u;
const uint _z = 0x07c4447cu;
const uint _0 = 0x746b58b8u;
const uint _1 = 0x23084238u;
const uint _2 = 0x744c88fcu;
const uint _3 = 0x744c18b8u;
const uint _4 = 0x19531f84u;
const uint _5 = 0xfc3c18b8u;
const uint _6 = 0x3221e8b8u;
const uint _7 = 0xfc422210u;
const uint _8 = 0x745d18b8u;
const uint _9 = 0x745e1130u;
const uint _space = 0x0000000u;
const uint _dot = 0x000010u;
const uint _minus = 0x0000e000u;
const uint _comma = 0x00000220u;
const uint _colon = 0x02000020u;

// Additional characters added by WoMspace <3
const uint _underscore = 0x000007Cu; // _
const uint _quote = 0x52800000u; // "
const uint _bang = 0x21084010u; // !
const uint _openBracket = 0x11084208u; // (
const uint _closeBracket = 0x41084220u; // )
const uint _openSquareBracket = 0x3908421Cu; // [
const uint _closeSquareBracket = 0xE1084270u; // ]
const uint _openChevron = 0x00888208u; // <
const uint _closeChevron = 0x02082220u; // >
const uint _block = 0xFFFFFFFCu; // █
const uint _copyright = 0x03AB9AB8u; // ©️

const int charWidth = 5;
const int charHeight = 6;
const int charSpacing = 1;
const int lineSpacing = 1;

const ivec2 charSize = ivec2(charWidth, charHeight);
const ivec2 spaceSize = charSize + ivec2(charSpacing, lineSpacing);

// Text renderer

struct Text {
    vec4 result; // Output color from the text renderer
    vec4 fgCol; // Text foreground color
    vec4 bgCol; // Text background color
    ivec2 fragPos; // The position of the fragment (can be scaled to adjust the
                    // size of the text)
    ivec2 textPos; // The position of the top-left corner of the text
    ivec2 charPos; // The position of the next character in the text
    int base; // Number base
    int fpPrecision; // Number of decimal places to print
} text;

// Fills the global text object with default values
void beginText(ivec2 fragPos, ivec2 textPos) {
    text.result = vec4(0.0);
    text.fgCol = vec4(1.0);
    text.bgCol = vec4(0.0, 0.0, 0.0, 0.6);
    text.fragPos = fragPos;
    text.textPos = textPos;
    text.charPos = ivec2(0);
    text.base = 10;
    text.fpPrecision = 2;
}

// Applies the rendered text to the fragment
void endText(inout vec3 sceneColor) {
    sceneColor = mix(sceneColor.rgb, text.result.rgb, text.result.a);
}

void printLine() {
    text.charPos.x = 0;
    ++text.charPos.y;
}

void printChar(uint character) {
    ivec2 pos = text.fragPos - text.textPos
        - spaceSize * text.charPos * ivec2(1, -1) + ivec2(0, spaceSize.y);

    uint index = uint(charWidth - pos.x + pos.y * charWidth + 1);

    // Draw background
    if (clamp(pos, ivec2(0), spaceSize - 1) == pos) {
        text.result = mix(text.result, text.bgCol, text.bgCol.a);
    }

    // Draw character
    if (clamp(pos, ivec2(0), charSize - 1) == pos) {
        text.result = mix(
            text.result,
            text.fgCol,
            text.fgCol.a * float(character >> index & 1u)
        );
    }

    // Advance to next character
    text.charPos.x++;
}

#define print(string) \
    { \
        uint[] characters = uint[] string; \
        for (int i = 0; i < characters.length(); ++i) \
            printChar(characters[i]); \
    }

void printUnsignedInt(uint value, int len) {
    const uint[36] digits = uint[](
        _0,
        _1,
        _2,
        _3,
        _4,
        _5,
        _6,
        _7,
        _8,
        _9,
        _a,
        _b,
        _c,
        _d,
        _e,
        _f,
        _g,
        _h,
        _i,
        _j,
        _k,
        _l,
        _m,
        _n,
        _o,
        _p,
        _q,
        _r,
        _s,
        _t,
        _u,
        _v,
        _w,
        _x,
        _y,
        _z
    );

    // Advance to end of the number
    text.charPos.x += len - 1;

    // Write number backwards
    for (int i = 0; i < len; ++i) {
        printChar(digits[int(value) % text.base]);
        value /= text.base;
        text.charPos.x -= 2;
    }

    // Return to end of the number
    text.charPos.x += len + 1;
}

void printUnsignedInt(uint value) {
    float logValue = log(float(value)) + 1e-6;
    float logBase = log(float(text.base));

    int len = int(ceil(logValue / logBase));
    len = max(len, 1);

    printUnsignedInt(value, len);
}

void printInt(int value) {
    if (value < 0) {
        printChar(_minus);
    }
    printUnsignedInt(uint(abs(value)));
}

void printFloat(float value) {
    if (value < 0.0) {
        printChar(_minus);
    }

    if (isnan(value)) {
        print((_N, _a, _N));
    } else if (isinf(value)) {
        print((_i, _n, _f));
    } else {
        float i, f = modf(abs(value), i);

        uint integralPart = uint(i);
        uint fractionalPart
            = uint(f * pow(float(text.base), float(text.fpPrecision)));

        printUnsignedInt(integralPart);
        printChar(_dot);
        printUnsignedInt(fractionalPart, text.fpPrecision);
    }
}

void printBool(bool value) {
    if (value) {
        print((_t, _r, _u, _e));
    } else {
        print((_f, _a, _l, _s, _e));
    }
}

void printVec3(vec3 value) {
    printFloat(value.x);
    print((_comma, _space));
    printFloat(value.y);
    print((_comma, _space));
    printFloat(value.z);
}

#endif // INCLUDE_UTILITY_TEXT_RENDERING


// https://github.com/GPUOpen-Effects/FidelityFX-cas

vec3 imageSharpenFilter(
    sampler2D sampler,
    ivec2 texel,
    vec3 center,
    float amount
) {
    if (amount <= 0.0) return center;

    vec3 left  = displayEotf(texelFetch(sampler, texel + ivec2(-1, 0), 0).rgb);
    vec3 right = displayEotf(texelFetch(sampler, texel + ivec2( 1, 0), 0).rgb);
    vec3 up    = displayEotf(texelFetch(sampler, texel + ivec2(0, -1), 0).rgb);
    vec3 down  = displayEotf(texelFetch(sampler, texel + ivec2(0,  1), 0).rgb);

    vec3 neighborhood = 0.25 * (left + right + up + down);
    vec3 detail = center - neighborhood;
    vec3 sharpened = center + detail * (0.9 * amount);

    vec3 lo = min(min(left, right), min(up, down));
    vec3 hi = max(max(left, right), max(up, down));
    return clamp(sharpened, lo, hi);
}

vec3 casFilter(sampler2D sampler, ivec2 texel, const float sharpness) {
#ifndef cas
    return displayEotf(texelFetch(sampler, texel, 0).rgb);
#endif

    // Fetch 3x3 neighborhood
    // a b c
    // d e f
    // g h i
    vec3 a = texelFetch(sampler, texel + ivec2(-1, -1), 0).rgb;
    vec3 b = texelFetch(sampler, texel + ivec2(0, -1), 0).rgb;
    vec3 c = texelFetch(sampler, texel + ivec2(1, -1), 0).rgb;
    vec3 d = texelFetch(sampler, texel + ivec2(-1, 0), 0).rgb;
    vec3 e = texelFetch(sampler, texel, 0).rgb;
    vec3 f = texelFetch(sampler, texel + ivec2(1, 0), 0).rgb;
    vec3 g = texelFetch(sampler, texel + ivec2(-1, 1), 0).rgb;
    vec3 h = texelFetch(sampler, texel + ivec2(0, 1), 0).rgb;
    vec3 i = texelFetch(sampler, texel + ivec2(1, 1), 0).rgb;

    // Convert to sRGB before performing cas
    a = displayEotf(a);
    b = displayEotf(b);
    c = displayEotf(c);
    d = displayEotf(d);
    e = displayEotf(e);
    f = displayEotf(f);
    g = displayEotf(g);
    h = displayEotf(h);
    i = displayEotf(i);

    // Soft min and max. These are 2x bigger (factored out the extra multiply)
    vec3 minColor = minOf(d, e, f, b, h);
    minColor += minOf(minColor, a, c, g, i);

    vec3 maxColor = maxOf(d, e, f, b, h);
    maxColor += maxOf(maxColor, a, c, g, i);

    // Smooth minimum distance to the signal limit divided by smooth max
    vec3 w = clamp01(min(minColor, 2.0 - maxColor) / maxColor);
    w = 1.0 - sqr(1.0 - w); // Shaping amount of sharpening
    w *= -1.0 / mix(8.0, 5.0, sharpness);

    // Filter shape:
    // 0 w 0
    // w 1 w
    // 0 w 0
    vec3 weightSum = 1.0 + 4.0 * w;
    return clamp01((b + d + f + h) * w + e) / weightSum;
}
#ifdef distanceView
uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec2 viewRes;
uniform vec2 taaOffset;

uniform float near;
uniform float far;

#include "/lib/util/lodMod.glsl"
#include "/lib/util/spaceConversion.glsl"
#endif

const int debugTextScale = 2;
ivec2 debugTextPosition = ivec2(0, int(viewHeight) / debugTextScale);

#if debugView == debugViewWeather
#if !defined INCLUDE_MISC_DEBUG_WEATHER
#define INCLUDE_MISC_DEBUG_WEATHER

uniform int worldTime;
uniform int worldDay;
uniform float sunAngle;

uniform float rainStrength;
uniform float wetness;

uniform vec3 lightDir;
uniform vec3 sunDir;
uniform vec3 moonDir;

uniform float worldAge;

uniform float timeSunrise;
uniform float timeNoon;
uniform float timeSunset;
uniform float timeMidnight;

uniform float biomeCave;
uniform float biomeTemperate;
uniform float biomeArid;
uniform float biomeSnowy;
uniform float biomeTaiga;
uniform float biomeJungle;
uniform float biomeSwamp;
uniform float biomeMayRain;
uniform float biomeMaySnow;
uniform float biomeTemperature;
uniform float biomeHumidity;

uniform float desertSandstormWeather;

#include "/lib/weather/clouds.glsl"
#include "/lib/weather/core.glsl"

void debugWeather(inout vec3 color) {
    const int numberCol = 30;

    Weather weather = getWeather();
    CloudsParams cloudsParams = getCloudsParams(weather);

    beginText(ivec2(gl_FragCoord.xy) / debugTextScale, debugTextPosition);
    text.bgCol = vec4(0.0);
    print((_W, _E, _A, _T, _H, _E, _R));
    printLine();
    print((_T, _e, _m, _p, _e, _r, _a, _t, _u, _r, _e));
    text.charPos.x = numberCol;
    printFloat(weather.temperature);
    printLine();
    print((_H, _u, _m, _i, _d, _i, _d, _i, _t, _y));
    text.charPos.x = numberCol;
    printFloat(weather.humidity);
    printLine();
    print(
        (_B, _i, _o, _m, _e, _space, _t, _e, _m, _p, _e, _r, _a, _t, _u, _r, _e)
    );
    text.charPos.x = numberCol;
    printFloat(biomeTemperature);
    printLine();
    print((_B, _i, _o, _m, _e, _space, _r, _a, _i, _n, _f, _a, _l, _l));
    text.charPos.x = numberCol;
    printFloat(biomeHumidity);
    printLine();
    print((_W, _i, _n, _d));
    text.charPos.x = numberCol;
    printFloat(weather.wind);
    printLine();
    print(
        (_T,
         _u,
         _r,
         _b,
         _u,
         _l,
         _e,
         _n,
         _c,
         _e)
    );
    text.charPos.x = numberCol;
    printFloat(weather.turbulence);
    printLine();
    printLine();
    print((_C, _L, _O, _U, _D, _S));
    printLine();
    print(
        (_C,
         _u,
         _m,
         _u,
         _l,
         _u,
         _s,
         _space,
         _c,
         _o,
         _n,
         _g,
         _e,
         _s,
         _t,
         _u,
         _s,
         _space,
         _b,
         _l,
         _e,
         _n,
         _d)
    );
    text.charPos.x = numberCol;
    printFloat(cloudsParams.cumulusCongestusBlend);
    printLine();
    print(
        (_L,
         _a,
         _y,
         _e,
         _r,
         _space,
         _0,
         _space,
         _c,
         _o,
         _v,
         _e,
         _r,
         _a,
         _g,
         _e,
         _space,
         _m,
         _i,
         _n)
    );
    text.charPos.x = numberCol;
    printFloat(cloudsParams.l0Coverage.x);
    printLine();
    print(
        (_L,
         _a,
         _y,
         _e,
         _r,
         _space,
         _0,
         _space,
         _c,
         _o,
         _v,
         _e,
         _r,
         _a,
         _g,
         _e,
         _space,
         _m,
         _a,
         _x)
    );
    text.charPos.x = numberCol;
    printFloat(cloudsParams.l0Coverage.y);
    printLine();
    print(
        (_L,
         _a,
         _y,
         _e,
         _r,
         _space,
         _0,
         _space,
         _c,
         _u,
         _m,
         _u,
         _l,
         _u,
         _s,
         _minus,
         _s,
         _t,
         _r,
         _a,
         _t,
         _u,
         _s,
         _space,
         _b,
         _l,
         _e,
         _n,
         _d)
    );
    text.charPos.x = numberCol;
    printFloat(cloudsParams.l0CumulusStratusBlend);
    printLine();
    print(
        (_L,
         _a,
         _y,
         _e,
         _r,
         _space,
         _1,
         _space,
         _c,
         _o,
         _v,
         _e,
         _r,
         _a,
         _g,
         _e,
         _space,
         _m,
         _i,
         _n)
    );
    text.charPos.x = numberCol;
    printFloat(cloudsParams.l1Coverage.x);
    printLine();
    print(
        (_L,
         _a,
         _y,
         _e,
         _r,
         _space,
         _1,
         _space,
         _c,
         _o,
         _v,
         _e,
         _r,
         _a,
         _g,
         _e,
         _space,
         _m,
         _a,
         _x)
    );
    text.charPos.x = numberCol;
    printFloat(cloudsParams.l1Coverage.y);
    printLine();
    print(
        (_L,
         _a,
         _y,
         _e,
         _r,
         _space,
         _1,
         _space,
         _c,
         _u,
         _m,
         _u,
         _l,
         _u,
         _s,
         _minus,
         _s,
         _t,
         _r,
         _a,
         _t,
         _u,
         _s,
         _space,
         _b,
         _l,
         _e,
         _n,
         _d)
    );
    text.charPos.x = numberCol;
    printFloat(cloudsParams.l1CumulusStratusBlend);
    printLine();
    print((_C, _i, _r, _r, _u, _s, _space, _a, _m, _o, _u, _n, _t));
    text.charPos.x = numberCol;
    printFloat(cloudsParams.cirrusAmount);
    printLine();
    print(
        (_C,
         _i,
         _r,
         _r,
         _o,
         _c,
         _u,
         _m,
         _u,
         _l,
         _u,
         _s,
         _space,
         _a,
         _m,
         _o,
         _u,
         _n,
         _t)
    );
    text.charPos.x = numberCol;
    printFloat(cloudsParams.cirrocumulusAmount);
    printLine();
    print(
        (_N,
         _o,
         _c,
         _t,
         _i,
         _l,
         _u,
         _c,
         _e,
         _n,
         _t,
         _space,
         _a,
         _m,
         _o,
         _u,
         _n,
         _t)
    );
    text.charPos.x = numberCol;
    printFloat(cloudsParams.noctilucentAmount);
    printLine();
    print(
        (_C,
         _r,
         _e,
         _p,
         _u,
         _s,
         _c,
         _u,
         _l,
         _a,
         _r,
         _space,
         _r,
         _a,
         _y,
         _s,
         _space,
         _a,
         _m,
         _o,
         _u,
         _n,
         _t)
    );
    text.charPos.x = numberCol;
    printFloat(cloudsParams.crepuscularRaysAmount);
    printLine();
    endText(color);
}

#endif // INCLUDE_MISC_DEBUG_WEATHER
#endif

#ifdef framingTool
// Composition-guide line profile shared by the thirds/aspect/safe
// overlays at the end of main.
float framingLineProfile(float d) {
    return 1.0 - smoothstep(
        framingLineWidth * 0.5 - 0.5,
        framingLineWidth * 0.5 + 0.5,
        d
    );
}
#endif

void main() {
    ivec2 texel = ivec2(gl_FragCoord.xy);

    if (abs(MC_RENDER_QUALITY - 1.0) < 0.01) {
        // Sharpness runs from -1 (no sharpening) to 1 (strongest).
        fragmentColor
            = casFilter(colortex0, texel, 0.0);
    } else {
        fragmentColor = catmullRomFilterFastRgb(colortex0, uv, 0.6);
        fragmentColor = displayEotf(fragmentColor);
    }

    fragmentColor = imageSharpenFilter(
        colortex0,
        texel,
        fragmentColor,
        0.50
    );

    fragmentColor = dither8bit(fragmentColor, bayer16(vec2(texel)));

#if debugView == debugViewSampler
    if (clamp(texel, ivec2(0), ivec2(textureSize(debugSampler, 0))) == texel) {
        fragmentColor = texelFetch(debugSampler, texel, 0).rgb;
        fragmentColor = displayEotf(fragmentColor);
    }
#elif debugView == debugViewWeather
    debugWeather(fragmentColor);
#endif

#ifdef distanceView
    float depth
        = texelFetch(depthtex0, ivec2(uv * viewRes * taauViewportScale), 0).x;

    vec3 positionScreen = vec3(uv, depth);
    vec3 positionView
        = screenToViewSpace(gbufferProjectionInverse, positionScreen, true);

    bool isSky = depth == 1.0;

#ifdef LOD_MOD_ACTIVE
    float depthLod = texelFetch(lodDepthTex, texel, 0).x;
    bool isLod = isLodTerrain(depth, depthLod);

    if (isLod) {
        positionView = screenToViewSpace(
            lodProjectionMatrixInverse,
            vec3(uv, depthLod),
            true
        );
    }

    isSky = isSky && depthLod == 1.0;
#endif

#if distanceViewMethod == distanceViewDistance
    float dist = length(positionView);
#elif distanceViewMethod == distanceViewDepth
    float dist = -positionView.z;
#endif

    fragmentColor = isSky
        ? vec3(1.0)
        : vec3(clamp01(dist * rcp(distanceViewMaxDistance)));
#endif

#ifdef framingTool
    // Composition guides: rule-of-thirds grid, target aspect box and
    // safe-area rect. Overlaid last so grading never tints the guides.
    {
        vec2 framingRes = vec2(viewWidth, viewHeight);
        float guide = 0.0;
#ifdef framingThirds
        vec2 third = framingRes / 3.0;
        float thirdsDist = min(
            min(
                abs(gl_FragCoord.x - third.x),
                abs(gl_FragCoord.x - 2.0 * third.x)
            ),
            min(
                abs(gl_FragCoord.y - third.y),
                abs(gl_FragCoord.y - 2.0 * third.y)
            )
        );
        guide = max(guide, framingLineProfile(thirdsDist));
#endif
#ifdef framingAspect
        float screenAspect = framingRes.x / max(framingRes.y, 1.0);
        float aspectDist;
        if (screenAspect > framingAspectRatio) {
            float halfW = 0.5 * framingRes.y * framingAspectRatio;
            aspectDist = min(
                abs(gl_FragCoord.x - (0.5 * framingRes.x - halfW)),
                abs(gl_FragCoord.x - (0.5 * framingRes.x + halfW))
            );
        } else {
            float halfH = 0.5 * framingRes.x / max(framingAspectRatio, 1e-4);
            aspectDist = min(
                abs(gl_FragCoord.y - (0.5 * framingRes.y - halfH)),
                abs(gl_FragCoord.y - (0.5 * framingRes.y + halfH))
            );
        }
        guide = max(guide, framingLineProfile(aspectDist));
        vec2 safeQ = abs(gl_FragCoord.xy - 0.5 * framingRes)
            - 0.5 * framingRes * framingSafeArea;
        float safeDist = length(max(safeQ, vec2(0.0)))
            + min(max(safeQ.x, safeQ.y), 0.0);
        guide = max(guide, framingLineProfile(abs(safeDist)));
#endif
        fragmentColor = mix(fragmentColor, vec3(1.0), guide * framingOpacity);
    }
#endif
}

#include "/lib/buffers.glsl"
