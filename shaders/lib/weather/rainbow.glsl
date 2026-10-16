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

#if !defined INCLUDE_WEATHER_RAINBOW
#define INCLUDE_WEATHER_RAINBOW

#include "/lib/weather/core.glsl"

float get_rainbow_amount(Weather weather) {
    return max(wetness, 0.5 * linear_step(0.6, 1.0, weather.humidity))
        * float(1.0 - rainStrength);
}

#endif // INCLUDE_WEATHER_RAINBOW
