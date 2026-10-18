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

#if !defined INCLUDE_LIB_LODMOD
#define INCLUDE_LIB_LODMOD

/*
 * Utility include for LoD mod support (Distant Horizons and Voxy)
 */

#if defined DISTANT_HORIZONS
// --------------------
//   Distant Horizons
// --------------------

// Avoid duplicate declaration when already defined by program
#ifndef LUSTER_COLORTEX15_DECLARED
#define LUSTER_COLORTEX15_DECLARED
uniform sampler2D colortex15;
#endif

uniform sampler2D dhDepthTex;
uniform sampler2D dhDepthTex1;
uniform mat4 dhProjection;
uniform mat4 dhProjectionInverse;
uniform mat4 dhPreviousProjection;
uniform mat4 dhModelView;
uniform mat4 dhModelViewInverse;
uniform float dhNearPlane;
uniform float dhFarPlane;
uniform int dhRenderDistance;

uniform float combinedNear;
uniform float combinedFar;

uniform vec4 combinedProjectionMatrix0;
uniform vec4 combinedProjectionMatrix1;
uniform vec4 combinedProjectionMatrix2;
uniform vec4 combinedProjectionMatrix3;

uniform vec4 combinedProjectionMatrixInverse0;
uniform vec4 combinedProjectionMatrixInverse1;
uniform vec4 combinedProjectionMatrixInverse2;
uniform vec4 combinedProjectionMatrixInverse3;

#define combinedDepthTex colortex15
#define lodDepthTex dhDepthTex
#define lodDepthTexSolid dhDepthTex1
#define lodDepthTexShading lodDepthTex
#define lodDepthTexScale taauViewportScale
#define lodProjectionMatrix dhProjection
#define lodProjectionMatrixInverse dhProjectionInverse
#define lodPreviousProjectionMatrix dhPreviousProjection
#define lodRenderDistance dhRenderDistance
#define combinedProjectionMatrix \
    mat4( \
        combinedProjectionMatrix0, \
        combinedProjectionMatrix1, \
        combinedProjectionMatrix2, \
        combinedProjectionMatrix3 \
    )
#define combinedProjectionMatrixInverse \
    mat4( \
        combinedProjectionMatrixInverse0, \
        combinedProjectionMatrixInverse1, \
        combinedProjectionMatrixInverse2, \
        combinedProjectionMatrixInverse3 \
    )
#elif defined VOXY
// --------
//   Voxy
// --------

#ifndef LUSTER_COLORTEX15_DECLARED
#define LUSTER_COLORTEX15_DECLARED
uniform sampler2D colortex15;
#endif

uniform sampler2D vxDepthTexOpaque;
uniform sampler2D vxDepthTexTrans;
uniform mat4 vxProj;
uniform mat4 vxProjInv;
uniform mat4 vxProjPrev;
uniform int vxRenderDistance;

float combinedNear = near;
float combinedFar = float(16 * vxRenderDistance);

mat4 combinedProjectionMatrix = mat4(
    vec4(gbufferProjection[0][0], 0.0, 0.0, 0.0),
    vec4(0.0, gbufferProjection[1][1], 0.0, 0.0),
    vec4(
        gbufferProjection[2][0],
        gbufferProjection[2][1],
        (combinedFar + combinedNear) / (combinedNear - combinedFar),
        -1.0
    ),
    vec4(
        0.0,
        0.0,
        (2.0 * combinedFar * combinedNear) / (combinedNear - combinedFar),
        0.0
    )
);

mat4 combinedProjectionMatrixInverse = mat4(
    vec4(gbufferProjectionInverse[0][0], 0.0, 0.0, 0.0),
    vec4(0.0, gbufferProjectionInverse[1][1], 0.0, 0.0),
    vec4(
        0.0,
        0.0,
        0.0,
        -(combinedFar - combinedNear) / (2.0 * combinedFar * combinedNear)
    ),
    vec4(
        gbufferProjectionInverse[3][0],
        gbufferProjectionInverse[3][1],
        -1.0,
        (combinedFar + combinedNear) / (2.0 * combinedFar * combinedNear)
    )
);

#define combinedDepthTex colortex15
#define lodDepthTex vxDepthTexTrans
#define lodDepthTexSolid vxDepthTexOpaque
#define lodDepthTexShading lodDepthTexSolid
#define lodDepthTexScale 1.0
#define lodProjectionMatrix vxProj
#define lodProjectionMatrixInverse vxProjInv
#define lodPreviousProjectionMatrix vxProjPrev
#define lodRenderDistance (vxRenderDistance * 16)
#else
#define combinedNear near
#define combinedFar far
#define combinedProjectionMatrix gbufferProjection
#define combinedProjectionMatrixInverse gbufferProjectionInverse
#define combinedDepthTex depthtex1

#define sampleDepthTexture texture
#endif

bool isLodTerrain(float depth, float depthLod) {
    return depth >= 1.0 && depthLod < 1.0;
}

#endif // INCLUDE_LIB_LODMOD
