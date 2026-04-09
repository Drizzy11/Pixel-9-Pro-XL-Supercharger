# 🚀 Pixel 9 Pro Series Supercharger v2.3 BETA.1

[![Device](https://img.shields.io/badge/Device-Pixel_9_Pro_Series-blue?logo=google&logoColor=white)](https://store.google.com/)
[![SoC](https://img.shields.io/badge/SoC-Tensor_G4-orange)](https://github.com/Drizzy07x/Supercharger_Pixel_9_Pro_Series)
[![Version](https://img.shields.io/badge/Version-v2.3_BETA.1-yellow)](https://github.com/Drizzy07x/Supercharger_Pixel_9_Pro_Series)

**Developed by:** [Drizzy07x](https://github.com/Drizzy07x)  
**Target devices:** Pixel 9 Pro XL (`komodo`), Pixel 9 Pro (`caiman`), Pixel 9 (`comet`)  
**Channel:** Beta  
**Compatibility:** Android 16, Magisk, KernelSU

---

## ⚡ Vision
**Supercharger** is a systemless performance module designed specifically for the **Pixel 9 series** on **Tensor G4**. The `v2.3 BETA.1` branch is focused on refining real-world responsiveness with safer, cleaner and more device-aware tuning behavior before it is promoted to stable.

---

## 🧠 Beta Focus

### 1. 🧩 Safer Daily Tuning
- Fewer unnecessary writes during boot
- More selective tuning paths
- Less aggressive behavior on unsupported kernels

### 2. 🎯 Device-Aware Targeting
- Selective IRQ handling for relevant hardware only
- Cleaner handling of `cpu.uclamp.latency_sensitive`
- `vm.page-cluster=0` only when swap or zram is active

### 3. 🌡️ Better Runtime Awareness
- Dashboard temperature refresh every 5 minutes
- Description updates only when needed
- Lower noise in logs for non-critical skips

---

## 📊 Magisk Dashboard
The dashboard still:

- waits for full boot
- shows profile status plus battery temperature
- updates temperature slowly and conditionally
- avoids unnecessary `module.prop` rewrites

This keeps the module informative without turning the dashboard logic into a source of battery drain.

---

## 🔍 Audit Log
All actions are written to:

`/data/adb/modules/p9pxl_supercharger/debug.log`

You can inspect it with:

```sh
su -c cat /data/adb/modules/p9pxl_supercharger/debug.log
```

---

## ⚠️ Beta Notes
`v2.3 BETA.1` is intended for testing and validation. It is expected to be safer than older experimental builds, but behavior can still vary across kernels and ROMs. Test carefully and keep a backup before flashing.

---

**Supercharge your Pixel. Refine the Tensor.** 🚀

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-yellow?style=for-the-badge&logo=buy-me-a-coffee)](https://www.buymeacoffee.com/Drizzy_07)
