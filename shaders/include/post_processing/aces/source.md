# ACES reference

Luster's ACES RRT/ODT implementation is based on the Academy/ACES reference architecture and the ACES 1.x reference transforms, with the shader implementation arranged for GLSL. The arbitrary Luster-specific `1.6` exposure multiplier was removed from the operator so ACES responds only to the scene exposure produced by the renderer.

Official ACES release repository: https://github.com/aces-aswf/aces
Official OpenColorIO ACES configuration: https://github.com/AcademySoftwareFoundation/OpenColorIO-Config-ACES
