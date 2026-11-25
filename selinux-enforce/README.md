# XMSROM SELinux Enforcing Guard (KernelSU Module)

Modul KernelSU ini dipakai untuk menguji **SELinux Enforcing asli (`setenforce 1`)** pada port **XMSROM OneUI 9.5 (`SM-S948B` / POCO F5 `marble`)** sebelum rule-nya ditanam permanen ke dalam build ROM.

## Cara Kerja Modul
1. **`module/sepolicy.rule`**: Memuat 702 rule (`677 allow` + `25 allowxperm`) via `ksud`, mencakup ioctl f2fs `/data` (`0xf500-0xf5ff`), `hal_camera_default`/DSP SNPE, `SystemUI` (`system_prop`), `IMS Service` (`ril.twwan911Timer` / `moai_policy.json`), `Settings` Developer Options (`logpersistd_logging_prop` + HAL binder), pembacaan `/sepolicy_version` (`rootfs`), serta `sec_system_init_shell` pada `metadata_file`.
2. **`module/system/system_ext/etc/selinux/system_ext_seapp_contexts`**: Menambahkan pemetaan eksplisit `user=oem_5004`, `oem_5006`, `oem_5017`, `oem_5025`, `oem_5026`, dan `oem_5554` agar `zygote` melabeli aplikasi Samsung shared-UID (`ShareLive`, `MdxKitService`, `BeaconManager`, `CMHProvider`, `FaceService`, `SamsungPositioning`, `Knox`) ke `platform_app` / `ker_app` / `kpp_app`, tidak tertahan di `u:r:zygote:s0`.
3. **Stage Enforcing & Anti-bootloop Deadman Guard (`post-fs-data.sh` + `service.sh`)**:
   - Secara default (`stage=service`), `post-fs-data.sh` mem-bind-mount `system_ext_seapp_contexts` (`u:object_r:seapp_contexts_file:s0`) dan `ksud` menerapkan `sepolicy.rule` sebelum `zygote` aktif, lalu `service.sh` mengaktifkan `setenforce 1` tepat setelah `sys.boot_completed=1`.
   - Opsi `echo early > /data/adb/xmsrom_selinux/stage` tersedia untuk menguji `setenforce 1` sejak `post-fs-data.sh`.
   - Jika boot gagal mencapai `SystemUI` sehat, `boot_guard` tidak dihapus dan pada reboot berikutnya modul otomatis membuat `$MODDIR/disable` lalu kembali ke `Permissive`.
4. **Tombol Action di KernelSU Manager (`action.sh`)**: Mengumpulkan `avc: denied` sejak boot lalu menyimpannya ke `/data/adb/xmsrom_selinux/new_avc.rule` dalam format siap tempel ke `sepolicy.rule`.

## Build ZIP Modul (Maintainer)
```bash
python selinux-enforce/scripts/build_zip.py
```
Hasil paket tersimpan di `selinux-enforce/dist/xmsrom-selinux-enforce-v1.0.0.zip`.

## Cara Memindahkan ke Build ROM (Saat Sudah Stabil)
1. **Contexts**: Timpa `/system/system_ext/etc/selinux/system_ext_seapp_contexts` di ROM dengan [module/system/system_ext/etc/selinux/system_ext_seapp_contexts](module/system/system_ext/etc/selinux/system_ext_seapp_contexts).
2. **SEPolicy rules**: Konversi baris-baris di [module/sepolicy.rule](module/sepolicy.rule) menjadi `.cil` / `.te` di `plat_sepolicy.cil` / `system_ext_sepolicy.cil` dan selesaikan sisa denial fase early-boot (`dontaudit` pada `init`/`main`) sebelum mengubah `androidboot.selinux=permissive` di `bootconfig` menjadi `enforcing`.
