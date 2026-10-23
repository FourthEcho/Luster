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

#if !defined INCLUDE_ACES_MATRICES
#define INCLUDE_ACES_MATRICES

#include "/lib/util/color.glsl"

const mat3 ap0ToXyz = mat3(
    0.9525523959,
    0.0000000000,
    0.0000936786,
    0.3439664498,
    0.7281660966,
    -0.0721325464,
    0.0000000000,
    0.0000000000,
    1.0088251844
);
const mat3 xyzToAp0 = mat3(
    1.0498110175,
    0.0000000000,
    -0.0000974845,
    -0.4959030231,
    1.3733130458,
    0.0982400361,
    0.0000000000,
    0.0000000000,
    0.9912520182
);

const mat3 ap1ToXyz = mat3(
    0.6624541811,
    0.1340042065,
    0.1561876870,
    0.2722287168,
    0.6740817658,
    0.0536895174,
    -0.0055746495,
    0.0040607335,
    1.0103391003
);
const mat3 xyzToAp1 = mat3(
    1.6410233797,
    -0.3248032942,
    -0.2364246952,
    -0.6636628587,
    1.6153315917,
    0.0167563477,
    0.0117218943,
    -0.0082844420,
    0.9883948585
);

// Bradford chromatic adaptation matrix from d60 (ACES white point) to d65 (rec.
// 709 white point)
const mat3 d60ToD65 = mat3(
    0.9872240000,
    -0.0061132700,
    0.0159533000,
    -0.0075983600,
    1.0018600000,
    0.0053300200,
    0.0030725700,
    -0.0050959500,
    1.0816800000
);
const mat3 d65ToD60 = mat3(
    1.0130349240,
    0.0061053089,
    -0.0149709632,
    0.0076982300,
    0.9981648318,
    -0.0050320341,
    -0.0028413125,
    0.0046851556,
    0.9245066529
);

const mat3 ap0ToAp1 = ap0ToXyz * xyzToAp1;
const mat3 ap1ToAp0 = ap1ToXyz * xyzToAp0;

const mat3 rec709ToAp0 = rec709ToXyz * d65ToD60 * xyzToAp0;
const mat3 ap0ToRec709 = ap0ToXyz * d60ToD65 * xyzToRec709;
const mat3 rec709ToAp1 = rec709ToXyz * d65ToD60 * xyzToAp1;
const mat3 ap1ToRec709 = ap1ToXyz * d60ToD65 * xyzToRec709;
const mat3 rec2020ToAp0 = rec2020ToXyz * d65ToD60 * xyzToAp0;
const mat3 ap0ToRec2020 = ap0ToXyz * d60ToD65 * xyzToRec2020;
const mat3 rec2020ToAp1 = rec2020ToXyz * d65ToD60 * xyzToAp1;
const mat3 ap1ToRec2020 = ap1ToXyz * d60ToD65 * xyzToRec2020;

// Used for quantities that are multiplied by an illuminant, like the diffuse
// albedo. These take the white point of the light source
const mat3 rec709ToAp1Unlit = rec709ToXyz * xyzToAp1;
const mat3 rec2020ToAp1Unlit = rec2020ToXyz * xyzToAp1;
const mat3 displayP3ToAp1Unlit = displayP3ToXyz * xyzToAp1;
const mat3 adobeRgbToAp1Unlit = adobeRgbToXyz * xyzToAp1;

// Working (== display) <-> ACES. Lit variants go through the D65<->D60
// Bradford adapt like rec709/rec2020 above; unlit variants skip it.
#if displayGamut == displayGamutDciP3 || displayGamut == displayGamutDisplayP3
#define workingToAp0 (workingToXyzColor * d65ToD60 * xyzToAp0)
#define ap0ToWorking (ap0ToXyz * d60ToD65 * xyzToWorkingColor)
#define workingToAp1 (workingToXyzColor * d65ToD60 * xyzToAp1)
#define ap1ToWorking (ap1ToXyz * d60ToD65 * xyzToWorkingColor)
#define workingToAp1Unlit (workingToXyzColor * xyzToAp1)
#elif displayGamut == displayGamutRec2020
#define workingToAp0 rec2020ToAp0
#define ap0ToWorking ap0ToRec2020
#define workingToAp1 rec2020ToAp1
#define ap1ToWorking ap1ToRec2020
#define workingToAp1Unlit rec2020ToAp1Unlit
#elif displayGamut == displayGamutAdobeRgb
#define workingToAp0 (workingToXyzColor * d65ToD60 * xyzToAp0)
#define ap0ToWorking (ap0ToXyz * d60ToD65 * xyzToWorkingColor)
#define workingToAp1 (workingToXyzColor * d65ToD60 * xyzToAp1)
#define ap1ToWorking (ap1ToXyz * d60ToD65 * xyzToWorkingColor)
#define workingToAp1Unlit adobeRgbToAp1Unlit
#else // displayGamutSrgb
#define workingToAp0 rec709ToAp0
#define ap0ToWorking ap0ToRec709
#define workingToAp1 rec709ToAp1
#define ap1ToWorking ap1ToRec709
#define workingToAp1Unlit rec709ToAp1Unlit
#endif

#endif // INCLUDE_ACES_MATRICES
