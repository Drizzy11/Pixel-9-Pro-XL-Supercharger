# 🚀 Pixel 9 Pro Series Supercharger

![Version](https://img.shields.io/badge/Version-v1.6_Stable-brightgreen.svg)
![Architecture](https://img.shields.io/badge/Architecture-Tensor_G4_(Zumapro)-blue.svg)
![Magisk](https://img.shields.io/badge/Magisk-26.0%2B-orange.svg)

An elite, device-specific Magisk/KernelSU module engineered exclusively for the **Google Pixel 9 Pro Series**. This module replaces generic brute-force scripts with an **Intelligent Hardware Architecture**, exploiting the specific physical limits and capabilities of the Tensor G4 (Zumapro) kernel to deliver zero-lag UI fluidity, lightning-fast I/O, and lower ping without draining your battery.

Developed by **Drizzy_07**.

---

## ⚡ Core Engines (v1.6 Features)

### 🧠 Smart Storage Engine
Instead of fighting the stock kernel's UFS 4.0 physical limits, we exploit them. 
* **Massive Read-Ahead:** Boosts `read_ahead_kb` to **1024**, forcing the hardware to load giant data blocks at once.
* **Result:** Blazing fast app loading times and game rendering while maintaining Google's native battery efficiency.

### 🌐 Smart Network Engine
Optimized for 5G and Wi-Fi mobile environments where packet loss happens.
* **Cubic Optimization:** Fine-tuned the default `cubic` algorithm alongside the `fq` (Fair Queuing) discipline.
* **Socket Reuse:** Enables `tcp_tw_reuse` to instantly recycle dead connections, drastically dropping latency, lag spikes, and ping in competitive gaming.

### 🚧 Smart IRQ Balancing
The stock IRQ daemon wakes up the Prime core too often. We stop it and manually assign hardware nodes:
* **Efficiency Cores (0-6):** Handle background noise.
* **Mid Cores (4-6):** Pinned specifically for Network, Modem, and I/O processes.
* **Performance Cores (4-7):** Strictly reserved for the Touchpanel (`goodix`/`sec_ts`) to ensure absolute zero-lag scrolling and typing.

### 🎮 Legacy System & Memory Profiles
* **16GB RAM Dalvik Profiling:** Maximizes the Pixel 9 Pro's LPDDR5X RAM by expanding the VM heap size to `1g`, keeping more apps alive in the background.
* **SkiaVK Renderer:** Forces the UI to render using Vulkan, taking the load off the CPU and reducing thermal throttling.

### 🛡️ Deep Audit Engine
Ever wonder if a Magisk module is *actually* working? 
The Supercharger includes a military-grade Audit Engine. Three minutes after every boot, it writes a comprehensive `[PASS/FAIL]` report directly to the module's folder.

---

## 📱 Compatibility
Strictly designed for devices running the **Tensor G4** processor:
* Google Pixel 9
* Google Pixel 9 Pro
* Google Pixel 9 Pro XL
* Google Pixel 9 Pro Fold
* *Support: Android 14 / Android 15 (Stock & Custom ROMs)*

---

## ⚙️ Installation Instructions
1. Download the latest `Supercharger-v1.6.zip` from the [Releases](../../releases) section.
2. Open **Magisk** or **KernelSU**.
3. Go to the **Modules** tab.
4. Tap **Install from storage** and select the downloaded ZIP.
5. Reboot your device.
6. **Important:** Wait exactly 3 to 5 minutes after booting for the Smart Engine to complete its deployment and background audits.

---

## 📊 How to Check Your Audit Log
Want to see the magic happening?
1. Open any Root File Explorer (like MiXplorer or MT Manager).
2. Navigate to: `/data/adb/modules/Pixel9_Supercharger/` (Folder name may vary slightly).
3. Open the `debug.log` file.
4. You will see a beautiful wall of `[PASS]` statuses detailing every tweak applied to your specific hardware nodes!

---

## ⚠️ Disclaimer
* Your warranty is void.
* I am not responsible for bricked devices, dead SD cards, or thermonuclear war.
* Please do NOT use this alongside other "Performance", "Battery", or "Network" modules (like FDE.AI, Magneto, L-Speed). They will conflict with the Tensor G4-specific logic used here.

---
**Credits:** Thanks to the Android development community and XDA for the endless knowledge base.


[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-yellow?style=for-the-badge&logo=buy-me-a-coffee)](https://www.buymeacoffee.com/Drizzy_07)
