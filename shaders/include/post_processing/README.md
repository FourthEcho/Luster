# Luster tone-mapping modules

Each non-ACES operator is now isolated in its own directory under
`include/post_processing/`. `tonemap_operators.glsl` is only the compatibility
facade consumed by the color-grading pass.

Order exposed by the GUI:
1. ACES Fit
2. ACES Full
3. AgX
4. Hejl 2015
5. Hejl-Burgess
6. Lottes
7. Uncharted 2
8. Tech
9. Ozius
10. Reinhard
11. Reinhard-Jodie

ACES is intentionally left on the existing reference-quality implementation.
