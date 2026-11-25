# XMSROM OneUI 9.5 KernelSU Modules (`marble` / `SM-S948B`)

Repository for KernelSU Next modules targeting the XMSROM OneUI 9.5 port on POCO F5 (`marble`).

**Maintainer:** GustyxPower

## Modules

| Folder | Module ID | Purpose | Docs |
| :--- | :--- | :--- | :--- |
| `addons/` | `xmsrom_oneui95_addons` | Thin WebUI module + on-demand `.tar.xz` OneUI feature packs (`NoMount` + `Magic Mount`) | [addons/README.md](addons/README.md) |
| `selinux-enforce/` | `xmsrom_selinux_enforce` | SELinux Enforcing test guard (`702` policy rules, `oem_5xxx` `system_ext_seapp_contexts`, anti-bootloop rollback) | [selinux-enforce/README.md](selinux-enforce/README.md) |

## Quick Build

```bash
# 1. Build OneUI Add-ons packs + thin installer ZIP
python addons/scripts/build_all.py

# 2. Build SELinux Enforcing Guard ZIP
python selinux-enforce/scripts/build_zip.py
```
