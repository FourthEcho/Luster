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

#if !defined INCLUDE_UTILITY_RANDOM
#define INCLUDE_UTILITY_RANDOM

// http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/

const float phi1 = 1.6180339887; // Golden ratio, solution to x^2 = x + 1
const float phi2 = 1.3247179572; // Plastic constant, solution to x^3 = x + 1

float r1(int n, float seed) {
    const float alpha = 1.0 / phi1;
    return fract(seed + n * alpha);
}

float r1(int n) { return r1(n, 0.5); }

vec2 r2(int n, vec2 seed) {
    const vec2 alpha = 1.0 / vec2(phi2, phi2 * phi2);
    return fract(seed + n * alpha);
}

vec2 r2(int n) { return r2(n, vec2(0.5)); }

//----------------------------------------------------------------------------//

// https://nullprogram.com/blog/2018/07/31/

uint lowbias32(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}


float randNextFloat(inout uint state) {
    state = lowbias32(state);
    return float(state) / float(0xffffffffu);
}

vec4 randNextVec4(inout uint state) {
    return vec4(
        randNextFloat(state),
        randNextFloat(state),
        randNextFloat(state),
        randNextFloat(state)
    );
}

//----------------------------------------------------------------------------//

// Float hash functions from https://www.shadertoy.com/view/4djSRW
// License:
/*
Copyright (c)2014 David Hoskins.
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.*/
// Uncomment when needed

//*
float hash1(float p) {
    p = fract(p * .1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

//*/

/*
float hash1(vec2 p) {
    vec3 p3  = fract(vec3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
//*/

//*
float hash1(vec3 p3) {
    p3 = fract(p3 * .1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

//*/

/*
vec2 hash2(float p) {
    vec3 p3 = fract(vec3(p) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}
//*/

//*
vec2 hash2(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

//*/

//*
vec2 hash2(vec3 p3) {
    p3 = fract(p3 * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

//*/


/*
vec4 hash4(float p) {
    vec4 p4 = fract(vec4(p) * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.xxyz+p4.yzzw)*p4.zywx);
}
//*/

//*
vec4 hash4(vec2 p) {
    vec4 p4 = fract(vec4(p.xyxy) * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

//*/

//*
vec4 hash4(vec3 p) {
    vec4 p4 = fract(vec4(p.xyzx) * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

//*/

/*
vec4 hash4(vec4 p4) {
    p4 = fract(p4  * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy+33.33);
    return fract((p4.xxyz+p4.yzzw)*p4.zywx);
}
//*/

//----------------------------------------------------------------------------//

// One dimensional value noise
float noise1d(float x) {
    float i, f = modf(x, i);
    f = cubicSmooth(f);
    return mix(hash1(i), hash1(i + 1.0), f);
}

float bayer2(vec2 a) {
    a = floor(a);
    return fract(dot(a, vec2(0.5, 0.75)));
}

// Ordered Bayer cascade: each level adds the coarse pattern plus the fine
// pattern weighted so the sum stays in [0, 1) with mean ~= 0.5
float bayer4(vec2 a) { return bayer2(0.5 * a) + 0.25 * bayer2(a); }

float bayer8(vec2 a) { return bayer4(0.5 * a) + 0.0625 * bayer2(a); }

float bayer16(vec2 a) { return bayer8(0.5 * a) + 0.015625 * bayer2(a); }

float interleavedGradientNoise(vec2 pos) {
    return fract(52.9829189 * fract(0.06711056 * pos.x + (0.00583715 * pos.y)));
}

float interleavedGradientNoise(vec2 pos, int t) {
    return interleavedGradientNoise(pos + 5.588238 * (t & 63));
}

float dither8bit(float x, float pattern) {
    const vec2 mulAdd = vec2(1.0, -0.5) / 255.0;
    return clamp01(x + (pattern * mulAdd.x + mulAdd.y));
}

vec2 dither8bit(vec2 x, float pattern) {
    const vec2 mulAdd = vec2(1.0, -0.5) / 255.0;
    return clamp01(x + (pattern * mulAdd.x + mulAdd.y));
}

vec3 dither8bit(vec3 rgb, float pattern) {
    const vec2 mulAdd = vec2(1.0, -0.5) / 255.0;
    return clamp01(rgb + (pattern * mulAdd.x + mulAdd.y));
}

// ----------------------------------------
// Sampling (merged from sampling.glsl)
// ----------------------------------------

vec2 vogelDiscSample(int stepIndex, int stepCount, float rotation) {
    const float goldenAngle = 2.4;

    float r = sqrt(stepIndex + 0.5) / sqrt(float(stepCount));
    float theta = stepIndex * goldenAngle + rotation;

    return r * vec2(cos(theta), sin(theta));
}

vec3 uniformSphereSample(vec2 hash) {
    hash.x *= tau;
    hash.y = 2.0 * hash.y - 1.0;
    return vec3(
        vec2(sin(hash.x), cos(hash.x)) * sqrt(1.0 - hash.y * hash.y),
        hash.y
    );
}

// Smootherstep-filtered texture lookup.
// https://iquilezles.org/www/articles/texture/texture.htm
vec4 smoothFilter(sampler2D sampler, vec2 coord) {
    vec2 res = vec2(textureSize(sampler, 0));

    coord = coord * res + 0.5;

    vec2 i, f = modf(coord, i);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    coord = i + f;

    coord = (coord - 0.5) / res;
    return texture(sampler, coord);
}

// https://amietia.com/lambertnotangent.html
#endif // INCLUDE_UTILITY_RANDOM
