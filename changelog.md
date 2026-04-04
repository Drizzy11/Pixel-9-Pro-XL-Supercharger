# Changelog

All notable changes to the **Pixel 9 Pro Series Supercharger** project will be documented in this file.

## [2.0 Stable] - 2026-04-03

### 🚀 Major Highlights
* **Android 16 GKI Ready:** Fully adapted to the new Generic Kernel Image security restrictions in Android 16.
* **Thermal Efficiency Victory:** A/B testing on PCMark Work 3.0 proves v2.0 completely eliminates the thermal throttling spikes present in the stock kernel, maintaining a flat temperature line under heavy loads.
* **I/O Speed Boost:** Achieved 22,098 in PCMark Writing tests, explicitly outperforming stock UFS speeds.

### ✨ Added
* **Android 16 Smart IRQ Extraction:** Added a new dynamic parsing method that reads directly from `/proc/interrupts` to bypass Android 16's strict hidden-directory permissions.
* **5G Elasticity TCP Buffers:** Injected massive `tcp_rmem` and `tcp_wmem` buffers specifically calculated to handle 5G packet loss and cell-tower handoffs seamlessly while moving.
* **Zero I/O Stats Overhead:** Implemented a new storage application tweak that forces `iostats` to `0` across `sda`, `sdb`, and `sdc` UFS blocks, saving background CPU cycles.

### 🔄 Changed
* **Touchpanel Routing:** Re-routed the Tensor G4 Touchpanel (`synaptics_tcm`) strictly to the Performance Cores (Mask `f0`) for flawless, zero-latency 120Hz scrolling.
* **Storage & Network Routing:** Pinned UFS Storage (`ufshcd`) and the 5G/Wi-Fi Modems (`exynos-pcie`, `dhdpcie`) strictly to the Mid-Cores (Mask `70`) to prevent background tasks from waking up the Prime core.

### 🗑️ Removed
* **ZRAM Algorithm Injection:** Removed the forced `lz4` compression tweak. Deep kernel auditing revealed Google hard-locked the Tensor G4's ZRAM to their proprietary `lz77eh` algorithm in Android 16. Removing this prevents silent background kernel rejections and keeps the `debug.log` 100% accurate.

---

## [1.6 Stable] - Previous Release
### ✨ Added
* Initial "Intelligent Hardware Architecture" implementation.
* 16GB RAM Profile optimization (Dalvik VM tweaks).
* Baseline Smart IRQ Balance for Android 14/15.
* 
