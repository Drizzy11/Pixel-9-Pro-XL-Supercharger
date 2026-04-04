# 🚀 Pixel 9 Pro XL Supercharger v2.1 STABLE

[![Device](https://img.shields.io/badge/Device-Pixel_9_Pro_XL-blue?logo=google&logoColor=white)](https://store.google.com/product/pixel_9_pro)
[![SOC](https://img.shields.io/badge/SOC-Tensor_G4-orange)](https://github.com/Drizzy07x/Pixel-9-Pro-XL-Supercharger)
[![Version](https://img.shields.io/badge/Version-v2.1_STABLE-green)](https://github.com/Drizzy07x/Pixel-9-Pro-XL-Supercharger)

**Developed by:** [Drizzy07x](https://github.com/Drizzy07x)  
**Target Device:** Pixel 9 Pro XL (Zumapro / Tensor G4)  
**Compatibility:** Android 16 (crDroid, AOSP, Stock)

---

## ⚡ The Vision
**Supercharger** is a low-level hardware optimization engine designed to bridge the gap between Google's stock software and the raw power of the **Tensor G4**. Unlike generic optimization scripts, Supercharger utilizes "Systemless" early-boot injections to reconfigure hardware routing, I/O pipelines, and the Android Runtime (ART) before the OS even breathes.

---

## 🛠️ The 4 Power Engines

### 1. 🧠 Early-Boot VM Injection (Zygote Shield)
By utilizing `system.prop` instead of late-stage shell commands, we inject memory parameters into the **Zygote** process at its inception.
* **1GB Heap Allocation:** Specifically tuned for the 16GB RAM model, allowing heavy applications to stay resident in memory without triggering aggressive Garbage Collection (GC) cycles.
* **Stable Multitasking:** Prevents Zygote/JNI fatal errors by ensuring the Virtual Machine inherits high-performance memory limits during the `post-fs-data` phase.

### 2. 🎮 Smart IRQ Balance (Hardware Affinity)
We bypass the standard `irqbalance` daemon to manually route hardware interrupts to the optimal CPU clusters.
* **Touch Priority:** The touch panel (`synaptics_tcm`) is pinned to the **Prime Cores** (f0) for near-zero input lag.
* **I/O Isolation:** Network and Storage interrupts are delegated to the **Mid Cores** (70), preventing "stutter" on the Prime cores during heavy downloads.

### 3. 💾 Ultra-Fast I/O Engine (UFS 4.0 Optimization)
Eliminates kernel bureaucracy in data handling to maximize the UFS 4.0 flash storage speeds.
* **Zero Latency:** Disk scheduler set to `none` to remove the overhead of software sorting.
* **1024KB Read-Ahead:** Quadruples the standard block size for reading data, drastically reducing loading times for massive games like *Battlefield* or *Genshin Impact*.

### 4. 🌐 Stable Network Buffering
A specialized networking stack optimized for 5G environments.
* **Massive TCP Buffers:** Increased to **16MB** to allow the modem to "burst" download data without packets stalling in the kernel queue.
* **TCP Cubic Stability:** Retains the gold standard of congestion control for maximum compatibility with Stock and Custom kernels.

---

## 📋 Technical Blueprint

| Parameter | Optimized Value | Benefit |
| :--- | :--- | :--- |
| **Dalvik Heap Start** | 32m | Faster initial app launch |
| **Dalvik Heap Growth** | 512m | Enhanced background multitasking |
| **Dalvik Heap Max** | 1024m | Real 16GB RAM utilization |
| **Touch Latency** | 0 | Instant UI response |
| **Read-Ahead KB** | 1024 | Industrial-grade storage throughput |
| **VFS Cache Pressure** | 60 | Balanced file system caching |

---

## 🔍 Auditing & Transparency
Supercharger includes a built-in deep audit engine. You can verify that every single engine is active and passed security checks by viewing the internal log:
`📂 /data/adb/modules/Pixel9_Supercharger/debug.log`

---

## ⚙️ Installation
1. Download the `Supercharger_v2.1_Stable.zip`.
2. Flash via **Magisk** or **KernelSU**.
3. Reboot.
4. *Optional:* Use a terminal emulator (like aShell) and type `su -c cat /data/adb/modules/Pixel9_Supercharger/debug.log` to confirm everything is running.

---

## ⚠️ Disclaimer
This module is designed for advanced users. While it has been rigorously tested on Android 16 (crDroid), the developer is not responsible for any damage to your device. Always keep a backup of your data.

---
**Supercharge your Pixel. Unleash the Tensor.** 🚀


[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-yellow?style=for-the-badge&logo=buy-me-a-coffee)](https://www.buymeacoffee.com/Drizzy_07)
