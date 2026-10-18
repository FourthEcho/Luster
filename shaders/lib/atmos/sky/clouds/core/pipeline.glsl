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

#if !defined INCLUDE_SKY_CLOUDS
#define INCLUDE_SKY_CLOUDS

#include "/lib/atmos/sky/clouds/altocumulus.glsl"
#include "/lib/atmos/sky/clouds/cirrus.glsl"
#include "/lib/atmos/sky/clouds/cumulus.glsl"
#include "/lib/atmos/sky/clouds/cumulusCongestus.glsl"
#include "/lib/atmos/sky/clouds/noctilucent.glsl"


bool cloudsEarlyExit(CloudsResult result, float r, float layerRadius) {
    bool hasCongestus = cloudsParams.cumulusCongestusBlend > eps;

    return result.transmittance < 1e-3 && r < layerRadius
        && (result.apparentDistance < cloudsCumulusCongestusDistance
            || !hasCongestus);
}

CloudsResult drawClouds(
    vec3 airViewerPos,
    vec3 rayDir,
    vec3 clearSky,
    float distanceToTerrain,
    float dither
) {
    CloudsResult result = cloudsNotHit;
    float r = length(airViewerPos);

#ifdef cloudsCumulus
    result = drawCumulusClouds(
        airViewerPos,
        rayDir,
        clearSky,
        distanceToTerrain,
        dither
    );
    if (cloudsEarlyExit(result, r, cloudsCumulusRadius)) {
        return result;
    }
#endif

#ifdef cloudsAltocumulus
    CloudsResult resultAc = drawAltocumulusClouds(
        airViewerPos,
        rayDir,
        clearSky,
        distanceToTerrain,
        dither
    );
    result = blendLayers(result, resultAc);
    if (cloudsEarlyExit(result, r, cloudsAltocumulusRadius)) {
        return result;
    }
#endif

#ifdef cloudsCumulusCongestus
    if (cloudsParams.cumulusCongestusBlend > eps) {
        CloudsResult resultCuCon = drawCumulusCongestusClouds(
            airViewerPos,
            rayDir,
            clearSky,
            distanceToTerrain,
            dither
        );

        // fade existing clouds into congestus
        float distanceFade = mix(
            1.0,
            resultCuCon.transmittance,
            linearStep(
                0.75,
                1.0,
                result.apparentDistance
                    * rcp(cloudsCumulusCongestusDistance)
            )
        );
        result.scattering *= distanceFade;
        result.transmittance
            += (1.0 - result.transmittance) * (1.0 - distanceFade);
        result.apparentDistance = mix(
            resultCuCon.apparentDistance,
            result.apparentDistance,
            distanceFade
        );

        result = blendLayers(result, resultCuCon);
        if (result.transmittance < 1e-3) {
            return result;
        }
    }
#endif

#ifdef cloudsCirrus
    CloudsResult resultCi = drawCirrusClouds(
        airViewerPos,
        rayDir,
        clearSky,
        distanceToTerrain,
        dither
    );
    result = blendLayers(result, resultCi);
    if (result.transmittance < 1e-3) {
        return result;
    }
#endif

#ifdef cloudsNoctilucent
    vec4 resultNlc
        = drawNoctilucentClouds(airViewerPos, rayDir, clearSky);
    result.scattering.rgb += resultNlc.xyz * result.transmittance;
    result.transmittance *= resultNlc.w;
#endif

    return result;
}

#endif // INCLUDE_SKY_CLOUDS
