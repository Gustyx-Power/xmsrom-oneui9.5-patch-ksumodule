# XMSROM QS Smoothness Tuning (`xmsrom_qs_perf` v2.0.0)

KernelSU Next module to eliminate Quick Settings lag/jank on the XMSROM One UI 9.5 (`SM-S948B`) port for POCO F5 (`marble`, 120Hz) while keeping `/system` clean via private `tmpfs` + `--bind` mount and `boot_guard` rollback protection.

## What It Changes

### Phase 1 — SurfaceFlinger & RenderEngine Props (`post-fs-data.sh`)
- `debug.sf.disable_client_composition_cache=0`
- `debug.sf.enable_layer_caching=1`
- `debug.sf.enable_planner_prediction=1`
- `debug.sf.predict_hwc_composition_strategy=1`
- `debug.renderengine.kawase2_off_critical_path=true`
- `debug.sf.set_idle_timer_ms=0`
- `ro.surface_flinger.use_content_detection_for_refresh_rate=false`

### Phase 2 — Patched `SystemUI.apk` & Prebuilt AOT `oat` (`scripts/patch_systemui.py`)
1. **`SecNotificationsQSContainerController$onInit$1.onLayoutChange`**: checks whether bounds changed and posts `SecNotificationsQSContainerController$onViewAttached$1` via `View.post()`, eliminating synchronous `requestLayout()` during layout.
2. **`QpRune.QUICK_PANEL_COMPOSE_DEBUG_LOG`** forced to `false` and `RecompositionLoggerKt` logging path bypassed while preserving Compose slot groups.
3. **`QSColorCurve`**: lowers peak Quick Settings blur radius from `250.0f` / `300.0f` to `110.0f` (`0x42dc0000`) so frosted glass remains intact with ~45% lower requested blur load.
4. **Hot per-frame `Log.d` removal**: drops unconditional string builds and `Log.d` calls in `PanelPopOverManager`, `SecPanelWindowBlurInteractor`, `SecPanelBackgroundBinder`, `SecPanelWindowBlurBinder` (`$1$1$1` & `$1$1$2`), and `QuickTileBoxKt$$ExternalSyntheticLambda4`.
5. **APK Integrity & ART Execution**: transplants original `APK Sig Block 42` (v2/v3 signer block, 4096-byte aligned after `zipalign -f -p 4`) and mounts read-only `tmpfs` with optional precompiled `oat/arm64/SystemUI.{odex,vdex}` (`dex2oat64 --compiler-filter=speed`) under `u:object_r:system_file:s0`.

## Measured Impact (`5fc99726` / `marble`, 120Hz, SELinux `Enforcing`)
- **QS 6-swipe `gfxinfo`**: Janky frames `5.95%` (Baseline) / `6.54%` (Phase 1) -> **`3.17%`** (Phase 2); 95th percentile `20ms` / `22ms` -> **`13ms`**; 99th `42ms` / `53ms` -> **`29ms`**; `Missed Vsync` `3.90%` -> **`1.20%`**.
- **Perfetto 9s trace**: `RE Completion` max wait `44.12ms` -> **`4.31ms`**; `finishFrame` total `776.68ms` -> **`110.73ms`**; `SystemUI` `layout` max `2.57ms` -> **`0.71ms`**; `improperly called during layout` & debug log spam -> **`0`**.

## Build Instructions (Maintainer)
```bash
# Patch SystemUI.apk -> qs-perf/staging/system/system_ext/priv-app/SystemUI/SystemUI.apk
python qs-perf/scripts/patch_systemui.py ../../SystemUI.apk

# Package installer ZIP -> qs-perf/dist/xmsrom-qs-perf-v2.0.0.zip
python qs-perf/scripts/build_zip.py
```

Note: Binary artifacts (`SystemUI.apk` / `SystemUI.odex` >100 MB) are excluded from Git via `.gitignore` (`staging/`, `dist/`). On-device AOT compilation (`dex2oat64 --compiler-filter=speed`) should be placed at `$MODDIR/system/system_ext/priv-app/SystemUI/oat/arm64/SystemUI.{odex,vdex}` if built against a different framework/ART build.
