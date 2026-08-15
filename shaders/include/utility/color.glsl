#if !defined INCLUDE_UTILITY_COLOR
#define INCLUDE_UTILITY_COLOR

const vec3 luminance_weights_rec709 = vec3(0.2126, 0.7152, 0.0722);
const vec3 luminance_weights_rec2020 = vec3(0.2627, 0.6780, 0.0593);
const vec3 luminance_weights_ap1 = vec3(0.2722, 0.6741, 0.0537);
#define luminance_weights luminance_weights_rec2020

// closest wavelengths to RGB primaries
const vec3 primary_wavelengths_rec709 = vec3(660.0, 550.0, 440.0);
const vec3 primary_wavelengths_rec2020 = vec3(660.0, 550.0, 440.0);
const vec3 primary_wavelengths_ap1 = vec3(630.0, 530.0, 465.0);
#define primary_wavelengths primary_wavelengths_rec2020

// -----------------------------------
//   Color space conversion matrices
// -----------------------------------

#define display_to_working_color rec709_to_rec2020
#define rec709_to_working_color rec709_to_rec2020

// Helper macro to convert sRGB colors to working space
#define from_srgb(x) (pow(x, vec3(2.2)) * rec709_to_rec2020)

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

// Display P3 (D65 white point, P3 primaries — Apple's native wide-gamut space)
const mat3 xyz_to_displayp3 = mat3(
    2.4934969,
    -0.9313836,
    -0.4027108,
    -0.8294890,
    1.7626641,
    0.0236247,
    0.0358458,
    -0.0761724,
    0.9568845
);
const mat3 displayp3_to_xyz = mat3(
    0.4865709,
    0.2656677,
    0.1982173,
    0.2289746,
    0.6917385,
    0.0792869,
    0.0000000,
    0.0451134,
    1.0439444
);

const mat3 rec2020_to_displayp3 = rec2020_to_xyz * xyz_to_displayp3;
const mat3 displayp3_to_rec2020 = displayp3_to_xyz * xyz_to_rec2020;
const mat3 rec709_to_displayp3 = rec709_to_xyz * xyz_to_displayp3;
const mat3 displayp3_to_rec709 = displayp3_to_xyz * xyz_to_rec709;

// Adobe RGB (1998) (D65 white point, wider red/green than sRGB, common on
// pro Mac displays and used in photo/print workflows)
const mat3 xyz_to_adobergb = mat3(
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
const mat3 adobergb_to_xyz = mat3(
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

const mat3 rec2020_to_adobergb = rec2020_to_xyz * xyz_to_adobergb;
const mat3 adobergb_to_rec2020 = adobergb_to_xyz * xyz_to_rec2020;

// -----------------------------------
//   Final display output color space
// -----------------------------------
// Selects BOTH the primaries matrix AND the transfer function (gamma
// curve) applied to working-space (Rec.2020) color right before output in
// program/final.fsh (via c19_color_grading.fsh for primaries). This is
// what makes the output actually native per mode instead of just
// reshuffled primaries with the wrong curve slapped on: sRGB and Display
// P3 legitimately share the sRGB OETF, but DCI-P3 (2.6 pure power gamma)
// and Adobe RGB (~2.2 pure power gamma) do not, so those get their own
// transfer function here rather than being forced through srgb_eotf.
//
// Driven by COLOR_OUTPUT_MODE (settings.glsl), which is itself defaulted
// per-profile in shaders.properties (low/medium = sRGB, high/ultra =
// Rec.2020, mac = Display P3).
//
// IMPORTANT: shaders.properties sets `supportsColorCorrection = true`,
// which tells Iris NOT to reinterpret/re-convert our output against its
// own currentColorSpace video setting. Without that flag Iris assumes
// every shaderpack outputs sRGB and silently re-maps colors on top of
// whatever we do here, which is the "Iris just changes some colors"
// double-conversion problem. With it, whatever we pick here is exactly
// what hits the actual GL drawable pixels.

// COLOR_OUTPUT_SRGB / COLOR_OUTPUT_REC2020 / COLOR_OUTPUT_DISPLAY_P3 /
// COLOR_OUTPUT_DCI_P3 / COLOR_OUTPUT_ADOBE_RGB / COLOR_OUTPUT_MODE are
// defined in settings.glsl (misc GUI screen).
#if COLOR_OUTPUT_MODE == COLOR_OUTPUT_REC2020
    const mat3 working_to_display_color = mat3(1.0); // working space already Rec.2020
    #define display_eotf srgb_eotf
    #define display_eotf_inv srgb_eotf_inv
#elif COLOR_OUTPUT_MODE == COLOR_OUTPUT_DISPLAY_P3
    #define working_to_display_color rec2020_to_displayp3
    #define display_eotf srgb_eotf
    #define display_eotf_inv srgb_eotf_inv
#elif COLOR_OUTPUT_MODE == COLOR_OUTPUT_DCI_P3
    // Same P3 primaries as Display P3; the real-world difference is the
    // theatrical 2.6 gamma curve instead of the sRGB OETF.
    #define working_to_display_color rec2020_to_displayp3
    #define display_eotf dci_p3_eotf
    #define display_eotf_inv dci_p3_eotf_inv
#elif COLOR_OUTPUT_MODE == COLOR_OUTPUT_ADOBE_RGB
    #define working_to_display_color rec2020_to_adobergb
    #define display_eotf adobe_rgb_eotf
    #define display_eotf_inv adobe_rgb_eotf_inv
#else
    #define working_to_display_color rec2020_to_rec709
    #define display_eotf srgb_eotf
    #define display_eotf_inv srgb_eotf_inv
#endif

vec3 srgb_eotf(vec3 linear) { // linear -> sRGB
    return 1.14374
        * (-0.126893 * linear + sqrt(linear)); // from Jodie in #snippets
}

vec3 srgb_eotf_inv(vec3 srgb) { // sRGB -> linear
    return srgb
        * (srgb * (srgb * 0.305306011 + 0.682171111)
           + 0.012522878); // https://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
}

// Pure power-law gamma, used where a display space's real transfer curve
// is a plain gamma rather than the sRGB piecewise/near-power curve.
vec3 gamma_eotf(vec3 linear, float gamma) { // linear -> gamma-encoded
    return pow(max(linear, vec3(0.0)), vec3(1.0 / gamma));
}

vec3 gamma_eotf_inv(vec3 encoded, float gamma) { // gamma-encoded -> linear
    return pow(max(encoded, vec3(0.0)), vec3(gamma));
}

// DCI-P3 theatrical gamma (SMPTE RP 431-2)
#define dci_p3_eotf(x) gamma_eotf(x, 2.6)
#define dci_p3_eotf_inv(x) gamma_eotf_inv(x, 2.6)

// Adobe RGB (1998) gamma (spec value 2.19921875, i.e. 563/256)
#define adobe_rgb_eotf(x) gamma_eotf(x, 2.19921875)
#define adobe_rgb_eotf_inv(x) gamma_eotf_inv(x, 2.19921875)

// -------------------------------------------------
//   Transformations between color representations
// -------------------------------------------------

// RGB <-> HSL

// from https://gist.github.com/983/e170a24ae8eba2cd174f
vec3 rgb_to_hsl(vec3 c) {
    const vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);

    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1e-6;

    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsl_to_rgb(vec3 c) {
    const vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);

    c.yz = clamp01(c.yz);

    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);

    return c.z * mix(K.xxx, clamp01(p - K.xxx), c.y);
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

float cie_lab_f(float t) {
    const float delta = 6.0 / 29.0;

    if (t > cube(delta)) {
        return pow(t, rcp(3.0));
    } else {
        return rcp(3.0 * delta * delta) * t + (4.0 / 29.0);
    }
}

float cie_lab_f_inv(float t) {
    const float delta = 6.0 / 29.0;

    if (t > delta) {
        return cube(t);
    } else {
        return (3.0 * delta * delta) * (t - (4.0 / 29.0));
    }
}

vec3 xyz_to_lab(vec3 xyz) {
    const vec3 xyz_n = vec3(95.0489, 100.0, 108.8840);

    xyz /= xyz_n;

    vec3 f = vec3(cie_lab_f(xyz.x), cie_lab_f(xyz.y), cie_lab_f(xyz.z));

    return vec3(116.0 * f.y - 16.0, 500.0 * (f.x - f.y), 200.0 * (f.y - f.z));
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
    const vec3 lambda = primary_wavelengths_rec2020;
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

// Isolate a range of hues
float isolate_hue(vec3 hsl, float center, float width) {
    if (hsl.y < 1e-2 || hsl.z < 1e-2) {
        return 0.0; // black/gray colors with no hue
    }
    return pulse(hsl.x * 360.0, center, width, 360.0);
}

#endif // INCLUDE_UTILITY_COLOR
