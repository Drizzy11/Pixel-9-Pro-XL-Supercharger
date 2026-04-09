## v2.3 BETA.1

This beta focuses on refining the module instead of making it more aggressive.  
The goal is to improve daily smoothness, safety, and device-awareness for the **Pixel 9 Pro XL / Pixel 9 Pro series**.

### Highlights
* Removed overly aggressive global IRQ behavior.
* Moved to more selective and safer tuning logic.
* Improved thermal and runtime awareness to protect stability and battery life.
* Reduced unnecessary boot-time writes and dashboard rewrites.
* Kept the module focused on real-world responsiveness instead of excessive tweaking.

### Changes
* Added `vm.page-cluster=0` only when swap or zram is actually active.
* Applied selective IRQ affinity only to relevant hardware categories.
* Improved handling of kernel-rejected IRQ affinity writes.
* Added direct `cpu.uclamp.latency_sensitive=1` tuning for `FOREGROUND_WINDOW` and `TOP-APP`.
* Kept temperature refresh on the Magisk dashboard slow and conditional for lower impact.
* Preserved boot safety by treating unsupported nodes as `SKIP` instead of hard failure where appropriate.

### Focus of this beta
* Better daily stability
* Better responsiveness
* Lower battery impact
* Cleaner boot behavior
* Safer device-aware tuning

### Notes
This beta is designed to validate smarter tuning behavior before a future stable release.  
It should feel cleaner and more predictable than older experimental builds while keeping the module lightweight and practical for everyday use.
