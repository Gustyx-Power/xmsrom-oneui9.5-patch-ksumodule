# XMSROM OneUI 9.5 Modular Add-ons (KernelSU Next)

Modul KernelSU sistemless berbasis **WebUI** untuk menambahkan fitur One UI 9.5 (`SM-S948B`) ke POCO F5 (`marble`) secara selektif dengan penyimpanan di `/data` agar partisi `/system` yang penuh tetap aman.

**Maintainer:** GustyxPower

---

## Arsitektur & Cara Kerja

1. **ZIP Modul Tipis (`< 100 KB`):** Flash sekali di KernelSU Next Manager. Tidak membawa APK ratusan MB di dalam installer awal.
2. **Download On-Demand via WebUI:** Buka WebUI modul dari KernelSU Next Manager, pilih hanya fitur yang diinginkan, lalu modul akan mengunduh arsip `.tar.xz` langsung via `curl` ke `/data`, memverifikasi hash `SHA-256`, dan mengekstraknya ke staging `system/`.
3. **Dual Mount Engine (`NoMount` + Built-in `Magic Mount`):**
   - Jika kernel sudah memakai **NoMount (`CONFIG_NOMOUNT`)** atau metamodule aktif (`meta-overlayfs` / `magic_mount`), modul menyerahkan mounting ke engine tersebut.
   - Jika memakai kernel standar tanpa metamodule eksternal (misalnya kernel `Palapa` pada `/data` `f2fs` yang tidak mendukung `overlayfs` langsung dari `/data`), `post-fs-data.sh` otomatis menjalankan **Magic Mount** (`tmpfs` + `mount --bind`) dengan konteks SELinux `u:object_r:system_file:s0`.

---

## Daftar Paket Add-on (`catalog.json`)

| ID | Fitur | Ukuran | Catatan |
| :--- | :--- | :--- | :--- |
| `bixby-core` | Bixby Assistant Core | ~90 MB | Asisten manual / tombol daya |
| `routines` | Modes & Routines | ~76 MB | Otomatisasi lengkap |
| `multisound` | Separate App Sound & Audio Mirroring | ~14 MB | Pisah suara per aplikasi (TWS vs speaker) |
| `edge-panels` | Clipboard/Tasks/Tools/People Edge + One-Handed | ~14 MB | `CocktailBarService` aktif bawaan |
| `live-effect` | Live Effect Portrait Engine | ~49 MB | Efek 3D foto wallpaper & Galeri |
| `video-editor` | Samsung Video Editor & Trimmer | ~70 MB | Edit & potong video Galeri |
| `photo-ai-editor` | AI Photo Editor, Remaster & Stickers | ~258 MB | Fitur online perlu akun Samsung |
| `ocr-provider` | Live Text / OCR Provider | ~151 MB | Ekstraksi teks dari gambar |
| `game-booster` | Game Booster, GOS & GPUWatch | ~28 MB | Overlay kontrol game & FPS monitor |
| `quickshare-smartview` | Quick Share & Smart View | ~37 MB | Berbagi file & screen cast TV |
| `link-to-windows` | Link to Windows | ~90 MB | Integrasi PC Windows |
| `bixby-vision` | Bixby Vision | ~31 MB | Pindai objek/teks kamera |
| `bixby-interpreter` | Interpreter, Call Assist & IntelliVoice | ~173 MB | Terjemahan langsung & asisten panggilan |
| `bixby-tts-id-en` | Samsung TTS Voices (`id-ID` & `en-US`) | ~108 MB | Paket suara offline |
| `smart-suggestions` | Personal Data Intelligence (Now Brief) | ~338 MB | Berat di RAM/storage |
| `bixby-wakeup` | Bixby Voice Wakeup (`Hi Bixby`) | ~100 MB | Eksperimental di HAL audio `taro` |

---

## Build & Upload (Maintainer)

```bash
# 1. Build seluruh paket .tar.xz, perbarui sha256 di catalog.json, dan buat ZIP modul
python scripts/build_all.py

# 2. Upload isi dist/packs/*.tar.xz + catalog.json ke Hugging Face Dataset
pip install huggingface_hub
set HF_TOKEN=hf_xxxxxxxxxxxxxxxxx
python scripts/upload_hf.py --repo GustyxPower/xmsrom-oneui9.5-addons

# 3. Upload dist/xmsrom-oneui9.5-addons-v1.0.0.zip ke GitHub Releases (tag v1.0.0)
```
