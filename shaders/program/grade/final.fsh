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

layout(location = 0) out vec3 fragment_color;

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
#include "/lib/util/dithering.glsl"
/*
--------------------------------------------------------------------------------

  GLSL Debug Text Renderer by SixthSurge (updated 2023-04-08)

  Character set based on Monocraft by IdreesInc
  https://github.com/IdreesInc/Monocraft

  With additional characters added by WoMspace

  Usage:

  // Call begin_text to initialize the text renderer. You can scale the fragment
position to adjust the size of the text begin_text(ivec2(gl_FragCoord.xy),
ivec2(0, viewHeight)); ^ fragment position     ^ text box position (upper left
corner)

  // You can print various data types
  print_bool(false);
  print_float(sqrt(-1.0)); // Prints "NaN"
  print_int(42);
  print_vec3(sky_color);

  // ...or arbitrarily long strings
  print((_H, _e, _l, _l, _o, _comma, _space, _w, _o, _r, _l, _d));

  // To start a new line, use
  print_line();

  // You can also configure the text color on the fly
  text.fg_col = vec4(1.0, 0.0, 0.0, 1.0);
  text.bg_col = vec4(0.0, 0.0, 0.0, 1.0);

  // ...as well as the number base and number of decimal places to print
  text.base = 16;
  text.fp_precision = 4;

  // Finally, call end_text to blend the current fragment color with the text
  end_text(scene_color);

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
const uint _open_bracket = 0x11084208u; // (
const uint _close_bracket = 0x41084220u; // )
const uint _open_square_bracket = 0x3908421Cu; // [
const uint _close_square_bracket = 0xE1084270u; // ]
const uint _open_chevron = 0x00888208u; // <
const uint _close_chevron = 0x02082220u; // >
const uint _block = 0xFFFFFFFCu; // █
const uint _copyright = 0x03AB9AB8u; // ©️

const int char_width = 5;
const int char_height = 6;
const int char_spacing = 1;
const int line_spacing = 1;

const ivec2 char_size = ivec2(char_width, char_height);
const ivec2 space_size = char_size + ivec2(char_spacing, line_spacing);

// Text renderer

struct Text {
    vec4 result; // Output color from the text renderer
    vec4 fg_col; // Text foreground color
    vec4 bg_col; // Text background color
    ivec2 frag_pos; // The position of the fragment (can be scaled to adjust the
                    // size of the text)
    ivec2 text_pos; // The position of the top-left corner of the text
    ivec2 char_pos; // The position of the next character in the text
    int base; // Number base
    int fp_precision; // Number of decimal places to print
} text;

// Fills the global text object with default values
void begin_text(ivec2 frag_pos, ivec2 text_pos) {
    text.result = vec4(0.0);
    text.fg_col = vec4(1.0);
    text.bg_col = vec4(0.0, 0.0, 0.0, 0.6);
    text.frag_pos = frag_pos;
    text.text_pos = text_pos;
    text.char_pos = ivec2(0);
    text.base = 10;
    text.fp_precision = 2;
}

// Applies the rendered text to the fragment
void end_text(inout vec3 scene_color) {
    scene_color = mix(scene_color.rgb, text.result.rgb, text.result.a);
}

void print_line() {
    text.char_pos.x = 0;
    ++text.char_pos.y;
}

void print_char(uint character) {
    ivec2 pos = text.frag_pos - text.text_pos
        - space_size * text.char_pos * ivec2(1, -1) + ivec2(0, space_size.y);

    uint index = uint(char_width - pos.x + pos.y * char_width + 1);

    // Draw background
    if (clamp(pos, ivec2(0), space_size - 1) == pos) {
        text.result = mix(text.result, text.bg_col, text.bg_col.a);
    }

    // Draw character
    if (clamp(pos, ivec2(0), char_size - 1) == pos) {
        text.result = mix(
            text.result,
            text.fg_col,
            text.fg_col.a * float(character >> index & 1u)
        );
    }

    // Advance to next character
    text.char_pos.x++;
}

#define print(string) \
    { \
        uint[] characters = uint[] string; \
        for (int i = 0; i < characters.length(); ++i) \
            print_char(characters[i]); \
    }

void print_unsigned_int(uint value, int len) {
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
    text.char_pos.x += len - 1;

    // Write number backwards
    for (int i = 0; i < len; ++i) {
        print_char(digits[int(value) % text.base]);
        value /= text.base;
        text.char_pos.x -= 2;
    }

    // Return to end of the number
    text.char_pos.x += len + 1;
}

void print_unsigned_int(uint value) {
    float log_value = log(float(value)) + 1e-6;
    float log_base = log(float(text.base));

    int len = int(ceil(log_value / log_base));
    len = max(len, 1);

    print_unsigned_int(value, len);
}

void print_int(int value) {
    if (value < 0) {
        print_char(_minus);
    }
    print_unsigned_int(uint(abs(value)));
}

void print_float(float value) {
    if (value < 0.0) {
        print_char(_minus);
    }

    if (isnan(value)) {
        print((_N, _a, _N));
    } else if (isinf(value)) {
        print((_i, _n, _f));
    } else {
        float i, f = modf(abs(value), i);

        uint integral_part = uint(i);
        uint fractional_part
            = uint(f * pow(float(text.base), float(text.fp_precision)));

        print_unsigned_int(integral_part);
        print_char(_dot);
        print_unsigned_int(fractional_part, text.fp_precision);
    }
}

void print_bool(bool value) {
    if (value) {
        print((_t, _r, _u, _e));
    } else {
        print((_f, _a, _l, _s, _e));
    }
}

void print_vec3(vec3 value) {
    print_float(value.x);
    print((_comma, _space));
    print_float(value.y);
    print((_comma, _space));
    print_float(value.z);
}

#endif // INCLUDE_UTILITY_TEXT_RENDERING


// https://github.com/GPUOpen-Effects/FidelityFX-cas

vec3 image_sharpen_filter(
    sampler2D sampler,
    ivec2 texel,
    vec3 center,
    float amount
) {
    if (amount <= 0.0) return center;

    vec3 left  = display_eotf(texelFetch(sampler, texel + ivec2(-1, 0), 0).rgb);
    vec3 right = display_eotf(texelFetch(sampler, texel + ivec2( 1, 0), 0).rgb);
    vec3 up    = display_eotf(texelFetch(sampler, texel + ivec2(0, -1), 0).rgb);
    vec3 down  = display_eotf(texelFetch(sampler, texel + ivec2(0,  1), 0).rgb);

    vec3 neighborhood = 0.25 * (left + right + up + down);
    vec3 detail = center - neighborhood;
    vec3 sharpened = center + detail * (0.9 * amount);

    vec3 lo = min(min(left, right), min(up, down));
    vec3 hi = max(max(left, right), max(up, down));
    return clamp(sharpened, lo, hi);
}

vec3 cas_filter(sampler2D sampler, ivec2 texel, const float sharpness) {
#ifndef cas
    return display_eotf(texelFetch(sampler, texel, 0).rgb);
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
    a = display_eotf(a);
    b = display_eotf(b);
    c = display_eotf(c);
    d = display_eotf(d);
    e = display_eotf(e);
    f = display_eotf(f);
    g = display_eotf(g);
    h = display_eotf(h);
    i = display_eotf(i);

    // Soft min and max. These are 2x bigger (factored out the extra multiply)
    vec3 min_color = min_of(d, e, f, b, h);
    min_color += min_of(min_color, a, c, g, i);

    vec3 max_color = max_of(d, e, f, b, h);
    max_color += max_of(max_color, a, c, g, i);

    // Smooth minimum distance to the signal limit divided by smooth max
    vec3 w = clamp01(min(min_color, 2.0 - max_color) / max_color);
    w = 1.0 - sqr(1.0 - w); // Shaping amount of sharpening
    w *= -1.0 / mix(8.0, 5.0, sharpness);

    // Filter shape:
    // 0 w 0
    // w 1 w
    // 0 w 0
    vec3 weight_sum = 1.0 + 4.0 * w;
    return clamp01((b + d + f + h) * w + e) / weight_sum;
}
#ifdef distanceView
uniform sampler2D depthtex0;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform vec2 view_res;
uniform vec2 taa_offset;

uniform float near;
uniform float far;

#include "/lib/misc/lodModSupport.glsl"
#include "/lib/util/spaceConversion.glsl"
#endif

const int debug_text_scale = 2;
ivec2 debug_text_position = ivec2(0, int(viewHeight) / debug_text_scale);

#if debugView == debugViewWeather
#if !defined INCLUDE_MISC_DEBUG_WEATHER
#define INCLUDE_MISC_DEBUG_WEATHER

uniform int worldTime;
uniform int worldDay;
uniform float sunAngle;

uniform float rainStrength;
uniform float wetness;

uniform vec3 light_dir;
uniform vec3 sun_dir;
uniform vec3 moon_dir;

uniform float world_age;

uniform float time_sunrise;
uniform float time_noon;
uniform float time_sunset;
uniform float time_midnight;

uniform float biome_cave;
uniform float biome_temperate;
uniform float biome_arid;
uniform float biome_snowy;
uniform float biome_taiga;
uniform float biome_jungle;
uniform float biome_swamp;
uniform float biome_may_rain;
uniform float biome_may_snow;
uniform float biome_temperature;
uniform float biome_humidity;

uniform float desert_sandstorm;

#include "/lib/weather/clouds.glsl"
#include "/lib/weather/core.glsl"

void debug_weather(inout vec3 color) {
    const int number_col = 30;

    Weather weather = get_weather();
    CloudsParameters clouds_params = get_clouds_parameters(weather);

    begin_text(ivec2(gl_FragCoord.xy) / debug_text_scale, debug_text_position);
    text.bg_col = vec4(0.0);
    print((_W, _E, _A, _T, _H, _E, _R));
    print_line();
    print((_T, _e, _m, _p, _e, _r, _a, _t, _u, _r, _e));
    text.char_pos.x = number_col;
    print_float(weather.temperature);
    print_line();
    print((_H, _u, _m, _i, _d, _i, _d, _i, _t, _y));
    text.char_pos.x = number_col;
    print_float(weather.humidity);
    print_line();
    print(
        (_B, _i, _o, _m, _e, _space, _t, _e, _m, _p, _e, _r, _a, _t, _u, _r, _e)
    );
    text.char_pos.x = number_col;
    print_float(biome_temperature);
    print_line();
    print((_B, _i, _o, _m, _e, _space, _r, _a, _i, _n, _f, _a, _l, _l));
    text.char_pos.x = number_col;
    print_float(biome_humidity);
    print_line();
    print((_W, _i, _n, _d));
    text.char_pos.x = number_col;
    print_float(weather.wind);
    print_line();
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
    text.char_pos.x = number_col;
    print_float(weather.turbulence);
    print_line();
    print_line();
    print((_C, _L, _O, _U, _D, _S));
    print_line();
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
    text.char_pos.x = number_col;
    print_float(clouds_params.cumulus_congestus_blend);
    print_line();
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
    text.char_pos.x = number_col;
    print_float(clouds_params.l0_coverage.x);
    print_line();
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
    text.char_pos.x = number_col;
    print_float(clouds_params.l0_coverage.y);
    print_line();
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
    text.char_pos.x = number_col;
    print_float(clouds_params.l0_cumulus_stratus_blend);
    print_line();
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
    text.char_pos.x = number_col;
    print_float(clouds_params.l1_coverage.x);
    print_line();
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
    text.char_pos.x = number_col;
    print_float(clouds_params.l1_coverage.y);
    print_line();
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
    text.char_pos.x = number_col;
    print_float(clouds_params.l1_cumulus_stratus_blend);
    print_line();
    print((_C, _i, _r, _r, _u, _s, _space, _a, _m, _o, _u, _n, _t));
    text.char_pos.x = number_col;
    print_float(clouds_params.cirrus_amount);
    print_line();
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
    text.char_pos.x = number_col;
    print_float(clouds_params.cirrocumulus_amount);
    print_line();
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
    text.char_pos.x = number_col;
    print_float(clouds_params.noctilucent_amount);
    print_line();
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
    text.char_pos.x = number_col;
    print_float(clouds_params.crepuscular_rays_amount);
    print_line();
    end_text(color);
}

#endif // INCLUDE_MISC_DEBUG_WEATHER
#endif

#ifdef framingTool
// Composition-guide line profile shared by the thirds/aspect/safe
// overlays at the end of main.
float framing_line_profile(float d) {
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
        fragment_color
            = cas_filter(colortex0, texel, 0.50 * 2.0 - 1.0);
    } else {
        fragment_color = catmull_rom_filter_fast_rgb(colortex0, uv, 0.6);
        fragment_color = display_eotf(fragment_color);
    }

    fragment_color = image_sharpen_filter(
        colortex0,
        texel,
        fragment_color,
        0.50
    );

    fragment_color = dither_8bit(fragment_color, bayer16(vec2(texel)));

#if debugView == debugViewSampler
    if (clamp(texel, ivec2(0), ivec2(textureSize(debugSampler, 0))) == texel) {
        fragment_color = texelFetch(debugSampler, texel, 0).rgb;
        fragment_color = display_eotf(fragment_color);
    }
#elif debugView == debugViewWeather
    debug_weather(fragment_color);
#endif

#ifdef distanceView
    float depth
        = texelFetch(depthtex0, ivec2(uv * view_res * taau_render_scale), 0).x;

    vec3 position_screen = vec3(uv, depth);
    vec3 position_view
        = screen_to_view_space(gbufferProjectionInverse, position_screen, true);

    bool is_sky = depth == 1.0;

#ifdef LOD_MOD_ACTIVE
    float depth_lod = texelFetch(lod_depth_tex, texel, 0).x;
    bool is_lod = is_lod_terrain(depth, depth_lod);

    if (is_lod) {
        position_view = screen_to_view_space(
            lod_projection_matrix_inverse,
            vec3(uv, depth_lod),
            true
        );
    }

    is_sky = is_sky && depth_lod == 1.0;
#endif

#if distanceViewMethod == distanceViewDistance
    float dist = length(position_view);
#elif distanceViewMethod == distanceViewDepth
    float dist = -position_view.z;
#endif

    fragment_color = is_sky
        ? vec3(1.0)
        : vec3(clamp01(dist * rcp(distanceViewMaxDistance)));
#endif

#ifdef framingTool
    // Composition guides: rule-of-thirds grid, target aspect box and
    // safe-area rect. Overlaid last so grading never tints the guides.
    {
        vec2 framing_res = vec2(viewWidth, viewHeight);
        float guide = 0.0;
#ifdef framingThirds
        vec2 third = framing_res / 3.0;
        float thirds_dist = min(
            min(
                abs(gl_FragCoord.x - third.x),
                abs(gl_FragCoord.x - 2.0 * third.x)
            ),
            min(
                abs(gl_FragCoord.y - third.y),
                abs(gl_FragCoord.y - 2.0 * third.y)
            )
        );
        guide = max(guide, framing_line_profile(thirds_dist));
#endif
#ifdef framingAspect
        float screen_aspect = framing_res.x / max(framing_res.y, 1.0);
        float aspect_dist;
        if (screen_aspect > framingAspectRatio) {
            float half_w = 0.5 * framing_res.y * framingAspectRatio;
            aspect_dist = min(
                abs(gl_FragCoord.x - (0.5 * framing_res.x - half_w)),
                abs(gl_FragCoord.x - (0.5 * framing_res.x + half_w))
            );
        } else {
            float half_h = 0.5 * framing_res.x / max(framingAspectRatio, 1e-4);
            aspect_dist = min(
                abs(gl_FragCoord.y - (0.5 * framing_res.y - half_h)),
                abs(gl_FragCoord.y - (0.5 * framing_res.y + half_h))
            );
        }
        guide = max(guide, framing_line_profile(aspect_dist));
        vec2 safe_q = abs(gl_FragCoord.xy - 0.5 * framing_res)
            - 0.5 * framing_res * framingSafeArea;
        float safe_dist = length(max(safe_q, vec2(0.0)))
            + min(max(safe_q.x, safe_q.y), 0.0);
        guide = max(guide, framing_line_profile(abs(safe_dist)));
#endif
        fragment_color = mix(fragment_color, vec3(1.0), guide * framingOpacity);
    }
#endif
}

#include "/lib/buffers.glsl"
