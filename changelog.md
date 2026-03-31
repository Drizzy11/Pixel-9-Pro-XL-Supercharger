# Pixel 9 Pro XL Supercharger - Change Log

All notable changes to the **Supercharger** project will be documented in this file.

## [v1.5 Stable] - 2026-03-31
### Added
- **Advanced Diagnostic Engine**: New `debug.log` system located at `/data/adb/modules/p9pxl_supercharger/`.
- **Hardware Monitoring**: Added SoC temperature logging and RAM status reporting (`free -m`) during boot.
- **Dynamic Magisk Dashboard**: The module description now updates in real-time to show if optimizations are active ✅ or bypassed ❌.
- **Automated Maintenance**: Integrated SQLite database VACUUM/REINDEX and background ART compiler (DexOpt) triggers for peak system health.

### Improved
- **16GB LPDDR5X Tuning**: Refined Dalvik VM properties (`heapgrowthlimit`, `heapsize`) for better multitasking stability.
- **UFS 4.0 I/O Path**: Optimized I/O schedulers and read-ahead buffers for near-instant app loading.
- **Thermal Efficiency**: Added power-save bias policies for Tensor G4 cores to maintain long-term hardware health.
- **UI Fluidity**: Forced SkiaVK renderer and increased touch responsiveness for a consistent 120Hz experience.

### Fixed
- **Boot Stability**: Increased stabilization delay to 90 seconds to ensure full compatibility with Evolution X and other A16 builds.
- **Cleanup**: Disabled redundant system telemetry (`statsd`) and live logcat to reduce idle battery drain.

---

## [v1.4 Stable] - 2026-03-30
- Initial public release for Pixel 9 Pro XL.
- Basic Dalvik VM and ZRAM optimizations.
- Support for Magisk v27+.
