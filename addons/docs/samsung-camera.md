# SamsungCamera patching on One UI 9.5 XGSI (`SM-S948B` on `marble`)

Everything below applies to `com.sec.android.app.camera` **17.5.00.69** shipped in the
`SM-S948BXXU6ZZKN` firmware and run on POCO F5 (`marble`). The camera APK is *not* part of
an addon pack yet - it is deployed straight into the module tree, so these notes double as
the build/deploy runbook.

## 1. Deployment layout

```
/data/adb/modules/xmsrom_oneui95_addons/
  system/priv-app/SamsungCamera/SamsungCamera.apk   # patched, still Samsung-signed
  system/cameradata/camera-feature.xml             # mode/resolution matrix
```

`post-fs-data.sh` magic-mounts `system/priv-app` and `system/cameradata` (see
`magic_mount_dir` calls), so replacing either file requires a reboot - the mounted copies
are what `PackageManager` / the camera process actually read.

## 2. Signer identity must be preserved (critical)

**Never `apksigner`/`uber-apk-signer` the camera APK with a debug key.** A re-signed build
still installs, but the app takes the unprivileged code path and dies on startup with:

```
java.lang.NoSuchMethodError: No static method asInterface(Landroid/os/IBinder;)
  Lcom/samsung/android/camera/ICameraServiceWorker;
    at CameraServiceWorkerWrapperImpl_V2.<init>
```

(leaving the launcher showing *"Kamera terus berhenti"*). The failure is purely the
signer identity: restoring the stock APK, or a dex-identical rebuild with the stock
`META-INF/CERT.*`, both run fine.

The ROM does not verify the v2/v3 digests, so the working recipe is:

1. keep the original `APK Signing Block` and `META-INF/CERT.*` byte-for-byte,
2. swap only the `classes*.dex` payloads that carry the patch,
3. patch `CRC32`, compressed size, uncompressed size (local header + central directory) and
   the local-header offsets, and leave the rest of the archive untouched.

`addons/scripts/repack_samsung_camera.mjs` does exactly that (no external deps).

## 3. Build & repack

```powershell
# 0. toolchain: apktool 3.0.3 + JDK 17
$apktool = 'C:\Users\Gustyx-Power\.local\bin\apktool.bat'

# 1. decode the stock APK once (dex stays untouched; -r skips resources for speed)
& $apktool d -f -r cam_fw/_chk/dev.apk -o cam_fw/dev_smali_full

# 2. edit smali in cam_fw/dev_smali_full (patch list in section 5)

# 3. rebuild; apktool only re-smali's the folders you touched
& $apktool b cam_fw/dev_smali_full -o cam_fw/newapk/rebuild.apk

# 4. swap the changed dex files back into the Samsung-signed original
node addons/scripts/repack_samsung_camera.mjs `
  --base    cam_fw/_chk/dev.apk `
  --rebuild cam_fw/newapk/rebuild.apk `
  --out     cam_fw/newapk/dev_samsung_signed.apk
```

`repack_samsung_camera.mjs` prints which entries changed, refuses a base without an APK
Signing Block, and verifies every replaced entry round-trips after writing.

## 4. Deploy

```powershell
adb push cam_fw/newapk/dev_samsung_signed.apk /data/local/tmp/cam.apk
adb shell 'su -c "cp /data/local/tmp/cam.apk /data/adb/modules/xmsrom_oneui95_addons/system/priv-app/SamsungCamera/SamsungCamera.apk && chmod 0644 /data/adb/modules/xmsrom_oneui95_addons/system/priv-app/SamsungCamera/SamsungCamera.apk"'
adb reboot
```

After the reboot the launcher icon works immediately; the first launch shows the usual
permission dialogs and the *"Aktifkan tag Lokasi?"* prompt on the first mode switch.

`camera-feature.xml` can also be re-mounted without a reboot for experiments:

```bash
su -c "mount --bind /data/adb/modules/xmsrom_oneui95_addons/system/cameradata/camera-feature.xml /system/cameradata/camera-feature.xml"
```

## 5. Patch inventory (relative to the stock `SM-S948BXXU6ZZKN` APK)

| dex | smali | patch | reason |
| :--- | :--- | :--- | :--- |
| `classes5.dex` | `fg/y.smali` | null-guard before using the `Landroid/util/Range;` field when the shutter is pressed in PRO | PRO shutter crashed with `NullPointerException` on `m:Landroid/util/Range;` |
| `classes2.dex` | `ue/j.smali` `S(Lcb/h0;Lcb/d0;)V` | `if-eqz p2, :skip_null_listener` in front of the listener notification | entering **VIDEO PRO** from the More panel crashed on `cb.d0.c0(IILcb/h0;)` because `yf.p0.D` (the pro audio-control presenter) is only created when `SUPPORT_PRO_VIDEO_AUDIO_INPUT_CONTROL` is on |
| `classes2.dex` | `yf/p0.smali` `m1()` | `if-eqz p0, :skip_audio_panel_stop` before `zf/c.stop()` | leaving **VIDEO PRO** crashed with `Attempt to invoke virtual method 'void zf.c.stop()' on a null object reference` |
| `classes5.dex` | `yf/m0.smali` (lambda) | `if-eqz p0, :skip_audio_panel_update` before `zf/c.l()` | same null presenter, reached from the audio-input-type callback |

`classes.dex`, `classes3.dex` and `classes4.dex` stay byte-identical to the firmware APK;
`classes2.dex` grows by 8 bytes and `classes5.dex` by 8 bytes for the four guards above.

## 6. `system/cameradata/camera-feature.xml`

Only two modes differ from the firmware file:

| mode | firmware | module | why |
| :--- | :--- | :--- | :--- |
| `SHOOTING_MODE_FOOD` | `enable="true"` | `enable="false"` | the port has no `libFoodDetector`, so the mode dies on entry |
| `SHOOTING_MODE_PANORAMA` | `enable="true"` | `enable="false"` | `PanoramaPhotoMaker.getMaxImageRate()` needs `SemCameraCharacteristics` field `J` (vendor lens view angles); the marble HAL returns `0.0f`, so `initializeMaker` throws `InvalidOperationException ... get invalid max imageRate with pictureSize 1920x1440`. Adding `capture-size`/`preview-size` to the mode only moves the crash deeper (`getResolution : argument is invalid - null`, then `-1`) |

The resolution matrix (`BACK_CAMERA_PICTURE_DEFAULT_RESOLUTION`, `..._4BY3_LARGE`,
`..._16BY9_LARGE`, front sizes, ...) is unchanged from the firmware file and is what makes
the port produce 1920x1440 stills on both cameras.

## 7. Verified on device (`5fc99726`, 2026-11-27)

| scenario | result |
| :--- | :--- |
| cold start / relaunch after reboot | OK, `pidof com.sec.android.app.camera` stable |
| rear photo (FOTO) | `20261127_025803.jpg`, 1920x1440, 883 KB |
| front photo | `20261127_025954.jpg`, 284 KB |
| rear video | 14.3 MB MP4, 6 s clip |
| front video | 1.3 MB MP4 |
| MALAM (Night) | `20261127_025854.jpg`, 880 KB |
| PRO photo (NPE fix) | `20261127_025825.jpg`, 879 KB, two consecutive shutter presses |
| VIDEO PRO | enters, records (345 MB for 2 min @ FHD30) and **exits without crash** |
| More panel | only PRO / VIDEO PRO / MALAM listed (FOOD and PANORAMA correctly hidden) |

## 8. Known limitations

- **Panorama**: disabled - needs Samsung vendor lens view angles that the marble HAL does not publish.
- **Food**: disabled - missing `libFoodDetector` native library.
- **Pro video audio panel**: the `Pensel - Omni` mic overlay appears, but the presenter object
  behind it is not created on this port; the guards above keep the app alive instead of
  showing the audio-control panel.
- Front-camera preview is dark in the test unit because the phone lies screen-up with the
  front camera covered; captures still succeed.

## 9. Rollback

Keep the untouched firmware APK (`cam_fw/_chk/dev.apk`) as the fallback: push it over the
module copy, reboot, and the camera behaves exactly like the stock firmware port again.

---

## Ringkasan (Bahasa Indonesia)

- APK SamsungCamera harus tetap memakai **tanda tangan Samsung**. Kalau di-*re-sign* dengan
  debug key, aplikasi langsung mati saat start (`NoSuchMethodError ... ICameraServiceWorker`).
  Karena ROM tidak memverifikasi digest v2/v3, cukup ganti isi `classes*.dex` di dalam APK
  asli memakai `addons/scripts/repack_samsung_camera.mjs`.
- Patch smali: null-guard shutter PRO (`fg/y`), null-guard listener mode (`ue/j.S`), dan
  null-guard presenter audio panel PRO VIDEO (`yf/p0.m1`, `yf/m0`).
- `camera-feature.xml`: `FOOD` dan `PANORAMA` dimatikan (library/vendor capability tidak ada di
  port ini); mode lain beserta resolusi 1920x1440 tetap seperti firmware.
- Sudah diverifikasi di perangkat: foto belakang/depan, video belakang/depan, MALAM, PRO,
  serta masuk-keluar VIDEO PRO tanpa crash.
