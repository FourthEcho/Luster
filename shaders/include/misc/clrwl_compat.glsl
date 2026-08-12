/*
--------------------------------------------------------------------------------

  include/misc/clrwl_compat:
  Fallback stub for the ColorWheel (clrwl_*) fragment hook.

  The Luster pack ships a set of `clrwl_*` program stubs that define
  `COLORWHEEL` and route the standard gbuffers/shadow programs through a
  user-supplied `clrwl_computeFragment` hook. That hook is intended to be
  provided by an external ColorWheel shader patch and is not present in
  the stock pack — so without this fallback, every `clrwl_*` program
  fails to compile with "'clrwl_computeFragment' : no matching
  overloaded function found".

  This file provides a safe no-op implementation that:
    * leaves the surface color unchanged (the texture sample is used
      verbatim, matching the behavior of the non-ColorWheel code path
      minus the biome tint),
    * leaves the light levels unchanged,
    * writes a default ambient-occlusion of 1.0 (fully lit),
    * writes a transparent overlay (no overlay texture).

  Runtime behavior: when a real ColorWheel patch is loaded, that patch
  should `#define` its own `clrwl_computeFragment` BEFORE this file is
  included (or `#undef INCLUDE_MISC_CLRWL_COMPAT` and re-include). The
  include guard on this file prevents accidental double-definition.

--------------------------------------------------------------------------------
*/

#if !defined INCLUDE_MISC_CLRWL_COMPAT
#define INCLUDE_MISC_CLRWL_COMPAT

#if defined COLORWHEEL && !defined clrwl_computeFragment
// Signature inferred from the five call sites in:
//   program/gbuffers_all_solid.fsh
//   program/gbuffers_all_translucent.fsh
//   program/gbuffers_armor_glint.fsh
//   program/gbuffers_damagedblock.fsh
//   program/shadow.fsh
//
//   void clrwl_computeFragment(
//       inout vec4 surface_color,   // texture sample, may be tinted in place
//       in    vec4 surface_color_in,// same value as surface_color (read-only copy)
//       inout vec2 light_levels,    // 0..1 blocklight/skylight, may be adjusted
//       out   float ao,             // ambient occlusion written by the hook
//       out   vec4  overlay_color   // overlay (e.g. grass) written by the hook
//   );
void clrwl_computeFragment(
    inout vec4 surface_color,
    in    vec4 surface_color_in,
    inout vec2 light_levels,
    out   float ao,
    out   vec4  overlay_color
) {
    // No-op fallback: preserve the sampled color, declare the surface
    // fully lit, and produce a transparent overlay. This matches the
    // behavior of the non-ColorWheel code path for the visible outputs
    // (color, AO, overlay); light levels are left untouched so the
    // post-call clamp in callers remains a no-op.
    surface_color = surface_color_in;
    ao = 1.0;
    overlay_color = vec4(0.0);
}

#endif // defined COLORWHEEL && !defined clrwl_computeFragment

#endif // INCLUDE_MISC_CLRWL_COMPAT
