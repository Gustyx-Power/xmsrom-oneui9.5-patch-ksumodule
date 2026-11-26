# XMSROM OneUI 9.5 KernelSU Modules (`marble` / `SM-S948B`)

Repository for KernelSU Next modules targeting the XMSROM OneUI 9.5 port on POCO F5 (`marble`).

**Maintainer:** GustyxPower

## Modules

| Folder | Module ID | Purpose | Docs |
| :--- | :--- | :--- | :--- |
| `addons/` | `xmsrom_oneui95_addons` | Thin WebUI module + on-demand `.tar.xz` OneUI feature packs (`NoMount` + `Magic Mount`) | [addons/README.md](addons/README.md) |
| `selinux-enforce/` | `xmsrom_selinux_enforce` | SELinux Enforcing test guard (`702` policy rules, `oem_5xxx` `system_ext_seapp_contexts`, anti-bootloop rollback) | [selinux-enforce/README.md](selinux-enforce/README.md) |
| `qs-perf/` | `xmsrom_qs_perf` | Quick Settings 120Hz smoothness (`1000ms` idle timer, Planner/Kawase2 props + `SystemUI` QS layout/log/blur & EdgeLighting Choreographer leak fixes + prebuilt `oat` mount) | [qs-perf/README.md](qs-perf/README.md) |
| `thermal-fix/` | `xmsrom_thermal_fix` | Daily thermal fix (masks `/system/priv-app/DigitalKey` cleanly at boot to stop GMS `dck_stub` respawn loop) | [thermal-fix/README.md](thermal-fix/README.md) |

## Quick Build

```bash
# 1. Build OneUI Add-ons packs + thin installer ZIP
python addons/scripts/build_all.py

# 2. Build SELinux Enforcing Guard ZIP
python selinux-enforce/scripts/build_zip.py

# 3. Patch SystemUI.apk (optional) & build QS Smoothness ZIP
python qs-perf/scripts/patch_systemui.py ../../SystemUI.apk
python qs-perf/scripts/build_zip.py

# 4. Build Daily Thermal Fix ZIP
python thermal-fix/scripts/build_zip.py
```
