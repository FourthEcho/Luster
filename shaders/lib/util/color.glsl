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

#if !defined INCLUDE_UTILITY_COLOR
#define INCLUDE_UTILITY_COLOR

const vec3 luminance_weights_rec709 = vec3(0.2126, 0.7152, 0.0722);
const vec3 luminance_weights_rec2020 = vec3(0.2627, 0.6780, 0.0593);
const vec3 luminance_weights_ap1 = vec3(0.2722, 0.6741, 0.0537);
const vec3 luminance_weights_display_p3 = vec3(0.2289746, 0.6917385, 0.0792869);
const vec3 luminance_weights_adobe_rgb = vec3(0.2973769, 0.6273491, 0.0752741);


#if displayGamut == displayGamutDciP3 || displayGamut == displayGamutDisplayP3
#define luminance_weights luminance_weights_display_p3
#elif displayGamut == displayGamutRec2020
#define luminance_weights luminance_weights_rec2020
#elif displayGamut == displayGamutAdobeRgb
#define luminance_weights luminance_weights_adobe_rgb
#else // displayGamutSrgb
#define luminance_weights luminance_weights_rec709
#endif

// closest wavelengths to RGB primaries
const vec3 primary_wavelengths_rec709 = vec3(660.0, 550.0, 440.0);
const vec3 primary_wavelengths_rec2020 = vec3(660.0, 550.0, 440.0);
const vec3 primary_wavelengths_ap1 = vec3(630.0, 530.0, 465.0);
const vec3 primary_wavelengths_display_p3 = vec3(660.0, 550.0, 440.0);
const vec3 primary_wavelengths_adobe_rgb = vec3(660.0, 550.0, 440.0);
#if displayGamut == displayGamutSrgb
#define primary_wavelengths primary_wavelengths_rec709
#elif displayGamut == displayGamutAdobeRgb
#define primary_wavelengths primary_wavelengths_adobe_rgb
#elif displayGamut == displayGamutDciP3 || displayGamut == displayGamutDisplayP3
#define primary_wavelengths primary_wavelengths_display_p3
#else // REC2020
#define primary_wavelengths primary_wavelengths_rec2020
#endif

// -----------------------------------
//   Color space conversion matrices
// -----------------------------------

// Working == display, so display<->working is identity. Vanilla Rec.709
// (sRGB) content still needs conversion into the active working gamut.
#if displayGamut == displayGamutDciP3
#define xyz_to_working_color (xyz_to_display_p3 * d65_to_dci_p3_white)
#define working_to_xyz_color (dci_p3_white_to_d65 * display_p3_to_xyz)
#define rec709_to_working_color (rec709_to_xyz * xyz_to_working_color)
#define display_to_working_color mat3(1.0)
#elif displayGamut == displayGamutDisplayP3
#define xyz_to_working_color xyz_to_display_p3
#define working_to_xyz_color display_p3_to_xyz
#define rec709_to_working_color (rec709_to_xyz * xyz_to_display_p3)
#define display_to_working_color mat3(1.0)
#elif displayGamut == displayGamutRec2020
#define xyz_to_working_color xyz_to_rec2020
#define working_to_xyz_color rec2020_to_xyz
#define rec709_to_working_color rec709_to_rec2020
#define display_to_working_color mat3(1.0)
#elif displayGamut == displayGamutAdobeRgb
#define xyz_to_working_color xyz_to_adobe_rgb
#define working_to_xyz_color adobe_rgb_to_xyz
#define rec709_to_working_color (rec709_to_xyz * xyz_to_adobe_rgb)
#define display_to_working_color mat3(1.0)
#else // displayGamutSrgb
#define xyz_to_working_color xyz_to_rec709
#define working_to_xyz_color rec709_to_xyz
#define rec709_to_working_color mat3(1.0)
#define display_to_working_color mat3(1.0)
#endif


#define working_to_display_color mat3(1.0)
// Working back to linear sRGB (for tonemap cores fitted to sRGB, e.g. AgX).
// Generic via XYZ so every branch stays exact; constant-folds at compile.
#define working_to_rec709_color (working_to_xyz_color * xyz_to_rec709)


#if displayGamut == displayGamutDciP3
#define from_display(x) (pow(x, vec3(2.6)))
#elif displayGamut == displayGamutDisplayP3
#define from_display(x) (pow(x, vec3(2.2)))
#elif displayGamut == displayGamutRec2020
#define from_display(x) (pow(x, vec3(2.4)))
#elif displayGamut == displayGamutAdobeRgb
#define from_display(x) (pow(x, vec3(2.2)))
#else // displayGamutSrgb
#define from_display(x) (pow(x, vec3(2.2)))
#endif


#if displayGamut == displayGamutRec2020
const float working_gamut_chroma = 1.35;
#elif displayGamut == displayGamutDciP3 || displayGamut == displayGamutDisplayP3
const float working_gamut_chroma = 1.18;
#elif displayGamut == displayGamutAdobeRgb
const float working_gamut_chroma = 1.12;
#else // displayGamutSrgb
const float working_gamut_chroma = 1.0;
#endif


#define gamut_expand(c) max(mix(vec3(dot((c), luminance_weights)), (c), working_gamut_chroma), vec3(0.0))

// Rec. 709 (sRGB primaries)
const mat3 xyz_to_rec709 = mat3(
    3.2406,
    -1.5372,
    -0.4986,
    -0.9689,
    1.8758,
    0.0415,
    0.0557,
    -0.2040,
    1.0570
);
const mat3 rec709_to_xyz = mat3(
    0.4124,
    0.3576,
    0.1805,
    0.2126,
    0.7152,
    0.0722,
    0.0193,
    0.1192,
    0.9505
);

// Rec. 2020 (working color space)
const mat3 xyz_to_rec2020 = mat3(
    1.7166084,
    -0.3556621,
    -0.2533601,
    -0.6666829,
    1.6164776,
    0.0157685,
    0.0176422,
    -0.0427763,
    0.94222867
);
const mat3 rec2020_to_xyz = mat3(
    0.6369736,
    0.1446172,
    0.1688585,
    0.2627066,
    0.6779996,
    0.0592938,
    0.0000000,
    0.0280728,
    1.0608437
);

const mat3 rec709_to_rec2020 = rec709_to_xyz * xyz_to_rec2020;
const mat3 rec2020_to_rec709 = rec2020_to_xyz * xyz_to_rec709;

// Display P3 (D65 primaries)
const mat3 display_p3_to_xyz = mat3(
    0.4865709,
    0.2656677,
    0.1982173,
    0.2289746,
    0.6917385,
    0.0792869,
    0.0,
    0.0451134,
    1.0439444
);
const mat3 xyz_to_display_p3 = mat3(
    2.4934969,
    -0.9313836,
    -0.4027108,
    -0.8294889,
    1.7626640,
    0.0236247,
    0.0358458,
    -0.0761724,
    0.9568845
);

// Adobe RGB (1998, D65)
const mat3 adobe_rgb_to_xyz = mat3(
    0.5767309,
    0.1855540,
    0.1881852,
    0.2973769,
    0.6273491,
    0.0752741,
    0.0270343,
    0.0706872,
    0.9911085
);
const mat3 xyz_to_adobe_rgb = mat3(
    2.0413690,
    -0.5649464,
    -0.3446944,
    -0.9692660,
    1.8760108,
    0.0415560,
    0.0134474,
    -0.1183897,
    1.0154096
);

const mat3 rec2020_to_display_p3 = rec2020_to_xyz * xyz_to_display_p3;
const mat3 display_p3_to_rec2020 = display_p3_to_xyz * xyz_to_rec2020;
const mat3 rec2020_to_adobe_rgb = rec2020_to_xyz * xyz_to_adobe_rgb;
const mat3 adobe_rgb_to_rec2020 = adobe_rgb_to_xyz * xyz_to_rec2020;


const mat3 srgb_to_lms = mat3(
    0.4122214708,
    0.5363325363,
    0.0514459929,
    0.2119034982,
    0.6806995451,
    0.1073969566,
    0.0883024619,
    0.2817188376,
    0.6299787005
);
const mat3 lms_to_srgb = mat3(
    4.0767416621,
    -3.3077115913,
    0.2309699292,
    -1.2684380046,
    2.6097574011,
    -0.3413193965,
    -0.0041960863,
    -0.7034186147,
    1.7076147010
);
const mat3 xyz_to_lms = xyz_to_rec709 * srgb_to_lms;
const mat3 lms_to_xyz = lms_to_srgb * rec709_to_xyz;

// Bradford chromatic adaptation D65 -> DCI-P3 theater white (0.314, 0.351)
const mat3 d65_to_dci_p3_white = mat3(
    0.976537,
    -0.015456,
    -0.016647,
    -0.025716,
    1.028549,
    -0.003772,
    -0.005699,
    0.011067,
    0.871363
);
// Inverse (DCI theater white -> D65) for working==display DCI-P3 round-trips.
const mat3 dci_p3_white_to_d65 = mat3(
    1.024541,
    0.015184,
    0.019639,
    0.025639,
    0.972578,
    0.004700,
    0.006375,
    -0.012253,
    1.147696
);
const mat3 rec2020_to_dci_p3
    = rec2020_to_display_p3 * d65_to_dci_p3_white;

// ------------------------------
//   Transfer functions (gamma)
// ------------------------------

vec3 srgb_eotf(vec3 linear) { // linear -> sRGB
    return 1.14374
        * (-0.126893 * linear + sqrt(linear)); // from Jodie in #snippets
}

vec3 srgb_eotf_inv(vec3 srgb) { // sRGB -> linear
    return srgb
        * (srgb * (srgb * 0.305306011 + 0.682171111)
           + 0.012522878); // https://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
}

// DCI-P3 theater transfer (gamma 2.6 power law)
vec3 dci_p3_eotf(vec3 linear) { return pow(linear, vec3(1.0 / 2.6)); }

vec3 dci_p3_eotf_inv(vec3 encoded) { return pow(encoded, vec3(2.6)); }

// Rec. 2020 SDR transfer (BT.1886 gamma 2.4 approximation)
vec3 rec2020_eotf(vec3 linear) { return pow(linear, vec3(1.0 / 2.4)); }

vec3 rec2020_eotf_inv(vec3 encoded) { return pow(encoded, vec3(2.4)); }

// Adobe RGB (1998) transfer (gamma 2.2 power law)
vec3 adobe_rgb_eotf(vec3 linear) { return pow(linear, vec3(1.0 / 2.2)); }

vec3 adobe_rgb_eotf_inv(vec3 encoded) { return pow(encoded, vec3(2.2)); }

// Display encoding follows displayGamut (Display P3 shares the sRGB
// transfer function, so it needs no dedicated EOTF)
#if displayGamut == displayGamutDciP3
#define display_eotf dci_p3_eotf
#define display_eotf_inv dci_p3_eotf_inv
#elif displayGamut == displayGamutRec2020
#define display_eotf rec2020_eotf
#define display_eotf_inv rec2020_eotf_inv
#elif displayGamut == displayGamutAdobeRgb
#define display_eotf adobe_rgb_eotf
#define display_eotf_inv adobe_rgb_eotf_inv
#else // displayGamutSrgb / displayGamutDisplayP3
#define display_eotf srgb_eotf
#define display_eotf_inv srgb_eotf_inv
#endif

// -------------------------------------------------
//   Transformations between color representations
// -------------------------------------------------


// from https://gist.github.com/983/e170a24ae8eba2cd174f
vec3 rgb_to_hsv(vec3 c) {
    const vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);

    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1e-6;

    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
    c.yz = clamp01(c.yz);

    vec3 rgb = clamp(
        abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
        0.0,
        1.0
    );

    return c.z * mix(vec3(1.0), rgb, c.y);
}

// RGB <-> YCoCg

// from https://en.wikipedia.org/wiki/YCoCg#Conversion_with_the_RGB_color_model
vec3 rgb_to_ycocg(vec3 rgb) {
    const mat3 cm = mat3(0.25, 0.5, 0.25, 0.5, 0.0, -0.5, -0.25, 0.5, -0.25);
    return rgb * cm;
}

vec3 ycocg_to_rgb(vec3 ycocg) {
    float tmp = ycocg.x - ycocg.z;
    return vec3(tmp + ycocg.y, ycocg.x + ycocg.z, tmp - ycocg.y);
}

// XYZ <-> LAB

float cie_lab_f_inv(float t) {
    const float delta = 6.0 / 29.0;

    if (t > delta) {
        return cube(t);
    } else {
        return (3.0 * delta * delta) * (t - (4.0 / 29.0));
    }
}

vec3 lab_to_xyz(vec3 lab) {
    const vec3 xyz_n = vec3(95.0489, 100.0, 108.8840);

    float y = lab.x * rcp(116.0) + (16.0 / 116.0);

    vec3 f_inv = vec3(
        cie_lab_f_inv(y + lab.y * rcp(500.0)),
        cie_lab_f_inv(y),
        cie_lab_f_inv(y - lab.z * rcp(200.0))
    );

    return xyz_n * f_inv;
}

// Original source:
// https://github.com/Jessie-LC/open-source-utility-code/blob/main/advanced/blackbody.glsl
vec3 blackbody(float temperature) {
    const vec3 lambda = primary_wavelengths;
    const vec3 lambda2 = lambda * lambda;
    const vec3 lambda5 = lambda2 * lambda2 * lambda;

    const float h = 6.63e-16; // Planck constant
    const float k = 1.38e-5; // Boltzmann constant
    const float c = 3.0e17; // Speed of light

    const vec3 a = lambda5 / (2.0 * h * c * c);
    const vec3 b = (h * c) / (k * lambda);
    vec3 d = exp(b / temperature);

    vec3 rgb = a * d - a;
    return min_of(rgb) / rgb;
}

// Isolate a range of hues (takes an HSV vector: hue, saturation, value)
float isolate_hue(vec3 hsv, float center, float width) {
    if (hsv.y < 1e-2 || hsv.z < 1e-2) {
        return 0.0; // black/gray colors with no hue
    }
    return pulse(hsv.x * 360.0, center, width, 360.0);
}

#endif // INCLUDE_UTILITY_COLOR
