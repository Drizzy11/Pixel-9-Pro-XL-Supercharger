# Pixel 9 Series Supercharger

<p align="center">
<a href="https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/releases/latest">
<img src="https://img.shields.io/github/v/release/Drizzy07x/Supercharger_Pixel_9_Series?style=for-the-badge&label=Release&color=34A853" alt="Latest release">
</a>
<a href="https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/releases">
<img src="https://img.shields.io/github/downloads/Drizzy07x/Supercharger_Pixel_9_Series/total?style=for-the-badge&label=Downloads&color=4285F4" alt="Total downloads">
</a>
<a href="https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/stargazers">
<img src="https://img.shields.io/github/stars/Drizzy07x/Supercharger_Pixel_9_Series?style=for-the-badge&label=Stars&color=F29900" alt="Stars">
</a>
<a href="LICENSE">
<img src="https://img.shields.io/github/license/Drizzy07x/Supercharger_Pixel_9_Series?style=for-the-badge&label=License&color=EA4335" alt="License">
</a>
</p>

<p align="center">
<img src="https://img.shields.io/badge/Device-Pixel%209%20Series-4285F4?style=flat-square&logo=google&logoColor=white" alt="Device">
<img src="https://img.shields.io/badge/SoC-Tensor%20G4-F29900?style=flat-square" alt="SoC">
<img src="https://img.shields.io/badge/Android-16%20QPR3%2B%20%26%2017-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android">
<img src="https://img.shields.io/badge/Root-Magisk%20%7C%20KernelSU%20%7C%20APatch-EA4335?style=flat-square" alt="Root">
<img src="https://img.shields.io/badge/Channel-Stable-101c30?style=flat-square" alt="Channel">
</p>

**Pixel 9 Series Supercharger** is a systemless performance, thermal, and maintenance module for the **Pixel 9 series on Tensor G4**.

The goal is simple: improve daily smoothness and responsiveness without turning the device into a reckless benchmark profile. Every change is applied best-effort, logged, and reversible from a WebUI dashboard.

<p align="center">
<a href="https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/releases/latest"><b>Download the latest release &rarr;</b></a>
</p>

<p align="center">
<img src="docs/images/webui-overview.png" alt="Supercharger WebUI dashboard showing module status, device information, and system health" width="820">
</p>

---

## Why This Module

- **Conservative by design.** No forced clocks in the stable profile, no thermal bypass, no charging override. If the kernel rejects a write, the setting is left unchanged instead of forced.
- **Everything is inspectable.** Boot tuning and dashboard actions are both logged, and a one-tap support snapshot collects the state needed to diagnose a problem.
- **Thermal Control is opt-in.** The thermal overlay is off after installation. You enable it yourself, once the phone has booted normally.
- **A real dashboard.** Profiles, thermal mode, maintenance, app optimization, and logs are all driven from the WebUI, not from hidden background behavior.

---

## Supported Devices

The installer verifies `ro.product.device` and aborts on anything else.

| Device           | Codename |
| ---------------- | -------- |
| Pixel 9          | `tokay`  |
| Pixel 9 Pro      | `caiman` |
| Pixel 9 Pro XL   | `komodo` |
| Pixel 9 Pro Fold | `comet`  |

Tuning targets the Tensor G4 platform rather than a single model, and every write is best-effort with a safe fallback. Devices outside the Pixel 9 series are not a target of this project.

### Requirements

- Android 16 QPR3+ or Android 17
- An unlocked bootloader with Magisk, KernelSU, or APatch installed
- Magisk 30.7 or newer when installing with Magisk (`minMagisk` 30700). Do not treat Magisk 31.0 as the floor until an official APK exists
- A root manager with WebUI support, to reach the dashboard
- On KernelSU / APatch 3.x, Integrated Thermal Control is a no-op unless a metamodule provides overlay/mount capability (`meta-overlayfs` and/or `meta-magicmount`). Supercharger does not ship a metamodule

---

## Installation

1. Download the latest `Pixel-9-Series-Supercharger-*.zip` from the [releases page](https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/releases/latest).
2. Optionally verify it against the published `.sha256` file.
3. Flash the ZIP from your root manager:
   - **Magisk** — *Modules* &rarr; *Install from storage* &rarr; select the ZIP
   - **KernelSU / APatch** — *Modules* &rarr; *Install* &rarr; select the ZIP
4. Reboot.
5. Open your root manager, find **Pixel 9 Series Supercharger**, and open its **WebUI** to reach the dashboard.

Thermal Control stays off until you enable it. Once the phone has booted normally, open *Profiles* &rarr; *Integrated Thermal Control* &rarr; **Enable Thermal Control**, then reboot again before judging behavior. On KernelSU / APatch 3.x the overlay is still a no-op unless a metamodule such as `meta-overlayfs` or `meta-magicmount` is already providing overlay/mount capability. Supercharger does not install that metamodule.

### Updating

The module publishes an update feed as a release asset, so Magisk, KernelSU, and APatch offer new versions in-app. You can also flash a newer ZIP over the installed module. Your selected performance profile and thermal profile survive the update.

### Uninstalling

Remove the module from your root manager and reboot. Uninstall stops the dashboard updater, clears persistent state under `/data/adb/supercharger_state`, and removes only the thermal request this module created, leaving an external Thermal Control add-on's registry intact.

---

## Screenshots

| Profiles and Thermal Control | Maintenance and app optimization |
| ---------------------------- | -------------------------------- |
| <img src="docs/images/webui-profiles.png" alt="Profile control and integrated thermal control panels" width="420"> | <img src="docs/images/webui-maintenance.png" alt="One-tap maintenance and app optimization panels" width="420"> |

> Dashboard previews rendered from the shipped WebUI source with sample status values.

---

## What the Module Does

Supercharger focuses on conservative, audited tuning rather than extreme changes.

### Current tuning direction

- Conservative virtual memory tuning
- Conditional `vm.page-cluster=0` when swap / zRAM is active
- Selective IRQ affinity for storage, network, and input paths when accepted by the kernel
- Safe block I/O tuning on valid physical devices only
- Conservative network tuning
- Read-only verification for selected system properties
- Best-effort writes with graceful fallback on unsupported kernels

---

## Profiles

### Active Smooth

Default daily profile focused on smoothness, safe boot behavior, and consistent responsiveness.

### Performance / Gaming

Experimental profile intended for gaming sessions and heavier foreground workloads. It includes expanded GPU devfreq discovery and a GPU floor fallback.

It uses best-effort writes and safe fallback behavior. If the kernel rejects a node, the module leaves it unchanged.

Reboot after switching profiles before judging behavior.

---

## Integrated Thermal Control

Thermal Control profiles are bundled into the main Supercharger module, but the thermal overlay is **off by default**.

This is intentional. The module does not place thermal config files under `system/vendor/etc` during installation. The user must enable Thermal Control manually from WebUI after confirming the device boots normally.

On KernelSU / APatch 3.x, the thermal overlay remains a no-op unless a metamodule (`meta-overlayfs` and/or `meta-magicmount`) is installed to provide overlay/mount capability. Supercharger does not implement or bundle that metamodule.

When enabled, Supercharger can keep the thermal profile aligned with the active performance profile:

| Performance profile  | Thermal profile |
| -------------------- | --------------- |
| Active Smooth        | `balanced`      |
| Performance / Gaming | `gaming`        |

`charge_cool` remains a manual Thermal-only profile for charging-focused behavior. Switching Thermal Control on, changing thermal profiles, or disabling it requires a reboot before judging behavior.

---

## WebUI Dashboard

The WebUI provides module status and maintenance controls without applying hidden changes by itself.

It reports:

- module health
- active profile
- root environment
- device model and codename
- Android release and SDK level
- battery temperature
- kernel and build info
- storage and network status
- integrated Thermal Control status

It also exposes:

- profile selection
- one-tap maintenance
- app optimization tools
- Android system dexopt job trigger
- manual Thermal Control enable / disable
- thermal profile selection for Balanced, Gaming, and Charge Cool
- logs
- support snapshot output

App optimization is incremental by default: Android can skip work it considers
unnecessary. Supercharger requests background priority when the platform supports
it, and reports performed, skipped, or failed results when ART provides that detail.
For an explicit retry, expand **Advanced: forced recompilation** and recompile only
the selected app. This can take longer and generate extra heat.

The app list is cached for up to one minute while using the dashboard; **Refresh
app list** reloads it immediately. Task polling pauses while the dashboard is
hidden and resumes when you return. The background task itself continues.

---

## Stability-First Design

This module is intentionally built around safe application and clean fallback behavior.

That means:

- no blind writes to unsupported nodes
- no global IRQ affinity
- no forced CPU/GPU clocks in the stable profile
- no thermal safety bypass
- no charging behavior override
- no version hacks tied rigidly to one Android build

The stable profile is designed to feel better in real use, not just look louder on paper.

---

## Troubleshooting

**The module installs but the WebUI will not open.**
The dashboard needs a root manager with WebUI support. Confirm your manager exposes a WebUI entry for installed modules, then reopen the module page.

**I switched profiles and nothing feels different.**
Profile changes need a reboot. Switch, reboot, then judge over normal daily use rather than a single benchmark run.

**Thermal Control shows as off after installing.**
That is the intended default. Enable it from *Profiles* &rarr; *Integrated Thermal Control* once the phone boots normally, then reboot.

**Thermal Control is enabled but nothing changes on KernelSU or APatch 3.x.**
Those root solutions need a metamodule (`meta-overlayfs` and/or `meta-magicmount`) for overlay mounts. Without one, the thermal overlay is a no-op. Install a metamodule from your root manager; Supercharger does not ship one.

**A tuning entry shows as skipped in the log.**
That is the fallback working. The kernel rejected that node, so the module left it unchanged instead of forcing it. Skipped entries are expected on some builds.

**Installation aborts with an incompatible device error.**
The installer only accepts the four Pixel 9 codenames listed above. Run `getprop ro.product.device` to confirm what your device reports.

**The device misbehaves after enabling Thermal Control.**
Disable Thermal Control from the WebUI and reboot. If the device will not boot far enough to reach the dashboard, remove the module from your root manager's recovery or safe mode, then open an issue with a support snapshot.

---

## Logs and Support Snapshot

The module keeps two separate logs under `/data/adb/modules/p9pxl_supercharger/`, both readable from the WebUI *Logs* tab:

| File                 | Contents                                                                       |
| -------------------- | ------------------------------------------------------------------------------ |
| `debug.log`          | Boot tuning report: what was applied, skipped, or rejected. Rewritten each boot |
| `debug.previous.log` | The boot report from the previous boot, kept for comparison                     |
| `maintenance.log`    | Running history of actions taken from the dashboard                             |

Because `debug.log` is rewritten on every boot, check it for what the current boot applied. Profile switches, Thermal Control changes, maintenance runs, and app optimization are recorded in `maintenance.log` instead, which accumulates across boots.

Support snapshots are written to:

```sh
/data/adb/modules/p9pxl_supercharger/support_snapshot.txt
```

The snapshot is regenerated by **Run maintenance** in the *Maintenance* tab. Run it first, then load and copy the snapshot from the *Support* tab and attach it to your report.

---

## Getting Help and Contributing

- [Report a bug](https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/issues/new?template=bug_report.yml)
- [Request a feature](https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/issues/new?template=feature_request.yml)
- [Ask a question](https://github.com/Drizzy07x/Supercharger_Pixel_9_Series/discussions)

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the design rules and the checks to run before opening a pull request, and [SECURITY.md](SECURITY.md) for reporting a security issue privately.

---

## Project Info

- **Current release:** v2.6.7 (Stable channel)
- **Module ID:** `p9pxl_supercharger`
- **Developed by:** [Drizzy07x](https://github.com/Drizzy07x)
- **Changelog:** [changelog.md](changelog.md)
- **License:** [MIT](LICENSE)

### Project Goals

- Improve day-to-day smoothness and responsiveness
- Keep tuning selective and device-aware
- Avoid unnecessary aggressive behavior
- Preserve battery life and thermal consistency where possible
- Maintain clean boot behavior and predictable runtime behavior
- Improve logging, diagnostics, and maintainability

---

## Support the Project

If you like the project and want to support future development, testing, and refinement:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Donate-yellow?style=for-the-badge&logo=buy-me-a-coffee)](https://www.buymeacoffee.com/Drizzy_07)

Starring the repository also helps other Pixel 9 owners find it.

---

## Credits

Credit to the Android, Magisk, KernelSU, APatch, and Pixel kernel development communities for the platform and tooling that make systemless development possible.
