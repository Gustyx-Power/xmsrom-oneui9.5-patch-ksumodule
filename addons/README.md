# XMSROM OneUI 9.5 Modular Add-ons (KernelSU Next)

[English](#english) · [Bahasa Indonesia](#bahasa-indonesia)

---

## English

A lightweight, **One UI-styled KernelSU Next WebUI** module for adding Samsung One UI 9.5 (`SM-S948B`) features onto POCO F5 (`marble`) on demand without consuming `/system` (`/` partition space stays untouched; all packs live in `/data`).

**Maintainer:** GustyxPower

### How It Works

1. **Thin Installer ZIP (`~20 KB`):** Flash once in KernelSU Next Manager. No multi-hundred-MB APKs are bundled inside the module ZIP itself.
2. **On-Demand WebUI Downloader:** Open the module's **WebUI** in KernelSU Next Manager, pick only the packs you want, and `addon_ctl.sh` downloads `.tar.xz` archives via `/system/bin/curl`, verifies `SHA-256`, and extracts into the module staging directory on `/data`.
3. **Dual Mount Engine (`NoMount` + Built-in `Magic Mount`):**
   - Automatically defers to kernel VFS **NoMount (`CONFIG_NOMOUNT`)** or an active KernelSU **metamodule** (`meta-overlayfs` / `magic_mount`) when present.
   - On standard kernels without `CONFIG_NOMOUNT` or external metamodules (such as custom kernels on `f2fs` `/data` where `overlayfs` rejects `/data` lowerdirs), `post-fs-data.sh` cleanly applies private `Magic Mount` (`busybox mount --make-private` + `tmpfs` + `--bind`) with `u:object_r:system_file:s0`.
4. **Bilingual WebUI (`EN / ID`):** Matches native Samsung One UI grouped list cards with AMOLED dark and light theme support.

### Add-on Catalog (`catalog.json`)

| Pack ID | Feature | Unpacked Size | Notes |
| :--- | :--- | :--- | :--- |
| `bixby-core` | Bixby Assistant Core | ~90 MB | Manual/side-button voice assistant |
| `routines` | Modes & Routines | ~76 MB | Full trigger/action automation |
| `multisound` | Separate App Sound & Audio Mirroring | ~14 MB | Split per-app audio between TWS and speaker |
| `edge-panels` | Clipboard/Tasks/Tools/People Edge + One-Handed | ~13 MB | Uses system `CocktailBarService` |
| `live-effect` | Live Effect & Portrait Engine | ~49 MB | 3D portrait effect engine for Gallery & wallpaper |
| `video-editor` | Samsung Video Editor & Trimmer | ~70 MB | Gallery video editing & trimming |
| `photo-ai-editor` | AI Photo Editor, Remaster & Stickers | ~258 MB | Cloud generative edits require Samsung Account |
| `ocr-provider` | Live Text & OCR Engine | ~151 MB | Text extraction from photos & screenshots |
| `game-booster` | Game Booster, GOS & GPUWatch | ~28 MB | In-game overlay & FPS/GPU metrics |
| `quickshare-smartview` | Quick Share & Smart View | ~73 MB | Nearby file share, Aware/MCF & P2P fix, Smart View casting |
| `link-to-windows` | Link to Windows (Phone Link) | ~90 MB | PC sync companion |
| `bixby-vision` | Bixby Vision | ~31 MB | Camera/Gallery visual scan |
| `bixby-interpreter` | Interpreter, Call Assist & IntelliVoice | ~173 MB | Live translation & call assist |
| `bixby-tts-id-en` | Samsung TTS Voices (`id-ID` & `en-US`) | ~108 MB | Offline speech voices |
| `smart-suggestions` | Personal Data Intelligence (Now Brief) | ~338 MB | Heavy; background context indexing |
| `lmc-cam` | LMC8.4 Camera (`org.codeaurora.snapcam`) | ~274 MB | Systemized GCam + `lib/arm64` native libs |
| `bixby-wakeup` | Bixby Voice Wakeup (`Hi Bixby`) | ~100 MB | Experimental on POCO F5 `taro` audio HAL |
| `samsung-camera` | Samsung Camera One UI 9.5 (patched `17.5.00.69`) | ~78 MB | Rear/front photo & video, Night, Pro, Video Pro; PANORAMA/FOOD off; reboot required |

### Maintainer Build & Release Commands

```bash
# 1. Build all .tar.xz packs, update catalog.json sha256/bytes, and build thin KSU ZIP
python addons/scripts/build_all.py

# 2. Upload dist/packs/*.tar.xz + catalog.json to Hugging Face Dataset
pip install huggingface_hub
set HF_TOKEN=hf_xxxxxxxxxxxxxxxxx
python addons/scripts/upload_hf.py --repo GustyxPower/xmsrom-oneui9.5-addons

# 2b. Or sync a single pack (catalog.json is always uploaded too)
python addons/scripts/upload_hf.py --repo GustyxPower/xmsrom-oneui9.5-addons --packs samsung-camera

# 3. Attach dist/xmsrom-oneui9.5-addons-v1.0.0.zip to GitHub Release tag v1.0.0
```

### SamsungCamera patches (signer identity)

The ported `com.sec.android.app.camera` 17.5.00.69 carries smali patches whose APK **must keep
its Samsung signature** (re-signing breaks the camera at startup). Build/repack/deploy steps and
the full patch inventory live in [`docs/samsung-camera.md`](docs/samsung-camera.md).

---

## Bahasa Indonesia

Modul KernelSU sistemless berbasis **WebUI bergaya One UI** untuk menambahkan fitur One UI 9.5 (`SM-S948B`) ke POCO F5 (`marble`) secara selektif dengan penyimpanan di `/data` agar partisi `/system` tetap lega.

**Maintainer:** GustyxPower

### Arsitektur & Cara Kerja

1. **ZIP Modul Tipis (`~20 KB`):** Flash sekali di KernelSU Next Manager tanpa membundel APK ratusan MB di dalam installer awal.
2. **Download On-Demand via WebUI:** Buka **WebUI** modul dari KernelSU Next Manager, pilih fitur yang diinginkan saja, lalu `addon_ctl.sh` mengunduh arsip `.tar.xz` via `/system/bin/curl`, memverifikasi `SHA-256`, dan mengekstraknya ke `/data`.
3. **Dual Mount Engine (`NoMount` + Built-in `Magic Mount`):**
   - Otomatis menyerahkan mounting jika kernel sudah memiliki **NoMount (`CONFIG_NOMOUNT`)** atau **metamodule** aktif (`meta-overlayfs` / `magic_mount`).
   - Pada kernel standar tanpa metamodule eksternal (termasuk kernel `Palapa` pada `/data` `f2fs` yang menolak `overlayfs` dari `/data`), `post-fs-data.sh` otomatis memakai **Magic Mount** (`busybox mount --make-private` + `tmpfs` + `--bind`) berlabel `u:object_r:system_file:s0`.
4. **Dukungan Bilingual (`EN / ID`):** Tombol ganti bahasa instan di header & pengaturan, lengkap dengan dukungan tema One UI Dark AMOLED dan Light mode.

### Daftar Paket Add-on (`catalog.json`)

Lihat tabel di atas untuk ID paket, perkiraan ukuran setelah ekstrak, dan catatan kompatibilitas per fitur.

### Build & Upload (Maintainer)

```bash
# 1. Build seluruh paket .tar.xz, perbarui sha256 di catalog.json, dan buat ZIP modul tipis
python addons/scripts/build_all.py

# 2. Upload isi dist/packs/*.tar.xz + catalog.json ke Hugging Face Dataset
pip install huggingface_hub
set HF_TOKEN=hf_xxxxxxxxxxxxxxxxx
python addons/scripts/upload_hf.py --repo GustyxPower/xmsrom-oneui9.5-addons

# 3. Upload dist/xmsrom-oneui9.5-addons-v1.0.0.zip ke GitHub Releases (tag v1.0.0)
```

### Patch SamsungCamera (tanda tangan APK)

APK `com.sec.android.app.camera` 17.5.00.69 yang diporting berisi patch smali dan **wajib tetap
bertanda tangan Samsung** (kalau di-*re-sign*, kamera mati saat start). Langkah build, repack,
deploy, dan daftar patch lengkap ada di [`docs/samsung-camera.md`](docs/samsung-camera.md).
