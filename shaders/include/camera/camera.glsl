#if !defined INCLUDE_CAMERA_CAMERA
#define INCLUDE_CAMERA_CAMERA

// ---------------------------------------------------------------------------
//   Physical camera: shared references and helpers
//
//   The exposure triangle (aperture N, shutter time t, sensitivity ISO) is
//   split across three programs — aperture drives DoF (c2_dof), shutter
//   drives motion blur (c20_motion_blur), ISO plus the full triangle drives
//   exposure (c4_taa_exposure) — so the reference setup they all normalize
//   against lives here, in one place: f/2.8, 1/60s, ISO 100. Change the
//   look of "neutral" once, here, instead of hunting matching constants.
//   User controls are CAM_SENSOR_WIDTH, CAM_FSTOPS, CAM_SHUTTER_SPEED,
//   CAM_ISO and CAM_EXPOSURE_COMPENSATION (see settings.glsl).
// ---------------------------------------------------------------------------

// Reference setup: every triangle factor is normalized to these, so the
// shipped defaults reproduce the pre-physical look exactly.
const float camera_reference_fstops = 2.8;
const float camera_reference_shutter = 60.0; // 1/60 s
const float camera_reference_iso = 100.0;

// Focal length in millimetres from the vertical FOV and the sensor height
// (sensor width shared across axes, height derived from aspect ratio).
float camera_sensor_height_mm(float aspect_ratio) {
    return float(CAM_SENSOR_WIDTH) / max(aspect_ratio, 1e-4);
}

float camera_focal_length_mm(float projection_11, float aspect_ratio) {
    float sensor_h = camera_sensor_height_mm(aspect_ratio);
    return 0.5 * sensor_h * projection_11;
}

// Thin-lens circle of confusion as a fraction of screen height:
// CoC = (f^2 / N) * |1/S - 1/D|, distances in metres.
float camera_coc_height_fraction(
    float focal_mm,
    float sensor_h,
    float focus_m,
    float dist_m
) {
    float coc_mm = focal_mm * focal_mm / max(CAM_FSTOPS, 1e-4)
        * abs(1.0 / (focus_m * 1000.0) - 1.0 / (dist_m * 1000.0));
    return coc_mm / max(sensor_h, 1e-4);
}

// Shutter trail factor relative to the 60Hz reference capture.
float camera_shutter_trail_factor() {
    return camera_reference_shutter / float(CAM_SHUTTER_SPEED);
}

// Closed-triangle exposure factor: t * ISO / N^2, normalized to the
// reference setup, times the EV compensation dial.
float camera_exposure_triangle_factor() {
    float t = camera_shutter_trail_factor();
    float iso = float(CAM_ISO) / camera_reference_iso;
    float n = camera_reference_fstops / max(CAM_FSTOPS, 1e-4);
    return t * iso * n * n * exp2(CAM_EXPOSURE_COMPENSATION);
}

#endif // INCLUDE_CAMERA_CAMERA
