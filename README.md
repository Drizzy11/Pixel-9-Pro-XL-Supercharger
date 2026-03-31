# Pixel 9 Pro XL Supercharger (v1.5 Final Stable) 🚀

The most advanced performance and efficiency engine specifically designed for the **Google Pixel 9 Pro XL (komodo)** running **Android 16 (Evolution X)**.

Developed by: **Drizzy_07**

---

## 🧠 Core Philosophy
This module transitions the Pixel 9 Pro XL from standard software constraints to a precision-tuned hardware-aware state. It focuses on maximizing the **16GB LPDDR5X RAM** and **UFS 4.0** storage while preserving the health of the **Tensor G4 SoC**.

---

## ✨ Key Features

### 📊 Evolutionary Visual Dashboard
* **Dynamic Status Tracking**: Real-time Magisk UI updates during the boot process: `[⏳] Initializing` -> `[🧠] Hardware` -> `[🌐] Connectivity` -> `[🚀] Active`.
* **Live Hardware Monitoring**: A 60-second background refresh loop displays the **Actual Temp** of the SoC directly in the Magisk Manager description.

### 🧠 16GB RAM & Multitasking (LPDDR5X)
* **Heap Optimization**: Locked Dalvik parameters (1GB Heap / 512MB Growth Limit) for extreme app retention.
* **VFS Pressure Tuning**: Reduced cache pressure to **50** to leverage high RAM capacity and minimize physical disk I/O.

### ⚡ UFS 4.0 Stability & Speed
* **Filesystem Safety Patch**: Resolved "Read-Only" storage errors and screenshot failures by capping `nr_requests` at **128**.
* **Intelligent Maintenance**: Background SQLite and ART optimization with a 180s delay and MediaProvider exclusion to ensure zero collisions with system tasks.
* **None Scheduler**: Forced `none` I/O scheduler and optimized 512KB read-ahead for instantaneous data access.

### 🌡️ Tensor G4 Thermal Control
* **Power Management**: Triple-cluster `powersave_bias` integration for maximum battery efficiency during idle states.
* **Capped Compilation**: Restricted background ART jobs to **4 threads** to prevent heat spikes and preserve battery longevity.

### 🌐 Connectivity & UI Fluidity
* **"Race to Sleep" Networking**: Aggressive TCP Fast Open (3) and Low Latency (1) tuning for optimized 5G and Wi-Fi 7 performance.
* **Graphics Engine**: Forced **SkiaVK** rendering and HW UI acceleration with dithering disabled for peak frame stability.
* **Touch Response**: Low-latency touch tuning via `resetprop` for ultra-responsive navigation.

---

## 🛠️ Installation
1. Download the `Supercharger-v1.5-Final.zip`.
2. Flash via **Magisk Manager**.
3. Reboot and wait **50 seconds** for the dashboard to initialize.
4. Check `/data/adb/modules/p9pxl_supercharger/debug.log` for a full diagnostic report.

---

## 📝 Compatibility
* **Device**: Google Pixel 9 Pro XL (komodo).
* **OS**: Android 16 (Tested on Evolution X).
* **Kernel**: Works with Stock or custom kernels.

---

## 🤝 Support & Development
This project is an ongoing effort to provide the best experience for the Pixel community. 

**Maintained by**: [Drizzy_07](https://github.com/Drizzy07x)

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-yellow?style=for-the-badge&logo=buy-me-a-coffee)](https://www.buymeacoffee.com/Drizzy_07)
