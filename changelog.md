# Changelog

All notable changes to the **Pixel 9 Pro XL Supercharger** project will be documented in this file.

# Changelog

## [1.5.1 Stable] - 2026-03-31
### **Fixed**
* **Networking**: Verified and re-applied TCP Fast Open (3) and Low Latency (1) for optimized 5G/Wi-Fi performance.
* **Performance Hangs**: Restored CPU scaling on clústeres P4/P7 to eliminate freezes during heavy gaming or multitasking.
* **UFS 4.0 Throughput**: Increased `nr_requests` and `read_ahead` for better data flow.

* 
## [1.5 Stable] - 2026-03-31

### **Added**
* **Evolutionary Dashboard**: Implemented a dynamic Magisk UI status system that updates in real-time during the boot process (`[⏳] Booting` -> `[🧠] Hardware Tuning` -> `[🌐] Connectivity` -> `[🚀] Active`).
* **Live Hardware Monitoring**: Added a 60-second background refresh loop to display the **Actual Temp** of the Tensor G4 SoC directly within the Magisk description.
* **Advanced Diagnostics**: Integrated a hardware-aware `debug.log` engine that captures SoC thermal metrics and initial 16GB LPDDR5X RAM snapshots upon deployment.

### **Changed**
* **RAM Efficiency (16GB Focus)**: Optimized Dalvik VM parameters (1GB Heap, 512MB Growth Limit, 32M Start) and reduced VFS Cache Pressure to 50 to maximize app retention and LPDDR5X memory throughput.
* **Network "Race to Sleep"**: Deployed aggressive TCP Fast Open (3) and Low Latency (1) parameters to minimize 5G and Wi-Fi 7 modem active states, significantly preserving battery life.
* **Thermal Management**: Applied a triple-cluster `powersave_bias` and capped ART compilation (dex2oat) to 4 threads to ensure the Tensor G4 remains cool during automated maintenance.
* **Maintenance Logic**: Stabilized background SQLite and ART optimization jobs with a 180s post-boot delay to prevent system-wide I/O collisions during the initial user session.

### **Fixed**
* **Filesystem Stability**: Resolved the persistent "Read-Only" storage errors and screenshot/deletion failures present since v1.4.
* **I/O Buffering**: Capped `nr_requests` at 128 for UFS 4.0 queues to match Android 16 kernel safety limits and prevent controller hangs.
* **MediaProvider Collision**: Implemented a strict path-exclusion rule for `com.android.providers.media` during SQLite maintenance to ensure 100% availability for media operations and gallery tasks.
* **Touch Logic**: Switched touch responsiveness tuning to a `resetprop` method to eliminate 'Error Code 1' diagnostics on Evolution X builds.

### **Performance**
* **Graphics Engine**: Forced SkiaVK rendering and HW UI acceleration while disabling system-wide dithering for peak frame stability and reduced GPU overhead.
* **UFS 4.0 Tuning**: Switched I/O scheduler to `none` and optimized read-ahead values to 512KB for instantaneous data access on high-speed storage.
* **System Silence**: Increased Wi-Fi scan intervals to 300s and disabled `statsd` and live logcat to reduce background CPU cycles and wakeups.

---

**Lead Developer**: Drizzy_07
**Target Architecture**: Google Pixel 9 Pro XL (komodo)
**OS Compatibility**: Android 16 / Tested in (Evolution X)
---

## [v1.4 Stable] - 2026-03-30
- Initial public release for Pixel 9 Pro XL.
- Basic Dalvik VM and ZRAM optimizations.
- Support for Magisk v27+.
