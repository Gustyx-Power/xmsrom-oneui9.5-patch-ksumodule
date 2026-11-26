# XMSROM Daily Thermal Fix (`xmsrom_thermal_fix` v1.0.0)

KernelSU Next module to stop excessive idle heating (~43°C battery temperature) caused by the `com.samsung.android.dkey` (`DigitalKey`) <-> Google Play Services `com.google.android.gms.dck_stub` restart loop on devices without UWB / StrongBox (`marble`).

## What It Fixes
- Masks `/system/priv-app/DigitalKey` via a private read-only `tmpfs` mount during `post-fs-data.sh` (with `skip_mount=1` so `/system` and overlay/magic mounts stay untouched).
- Adds a post-boot fallback in `service.sh` (`pm disable-user --user 0 com.samsung.android.dkey`) in case the package remains visible from another path.
- Prevents `ChimeraModuleLdr` from killing and respawning `com.google.android.gms` every 2–3 seconds along with repeated TEE KeyMint key generation and `system_server` / `logd` churn.

> [!NOTE]
> Samsung Digital Key (car key NFC/UWB) is disabled while this module is active. Uninstalling the module and rebooting restores `DigitalKey` automatically.

## Build ZIP (Maintainer)
```bash
python thermal-fix/scripts/build_zip.py
```
