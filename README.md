# Pixel 6a KSU Modules

**English | [Русский](README.ru.md)**

Standalone [KernelSU](https://kernelsu.org)/[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) modules for a personally owned, rooted **Pixel 6a**.

Developed and tested in a private lab environment (Pixel 6a, Android 16, build CP1A.260405.005, kernel 6.1.145). The modules are plain shell-script KSU modules — no kernel code, no exploit code, no bundled binaries beyond the scripts themselves.

## Modules

### DeVerizonficator v1.0
Unlocks non-Verizon SIMs on Verizon Pixel 6a SKUs.

Verizon devices ship with a SIM-lock carrier-restriction profile provisioned by Google's OOB (zero-touch) provisioning service. It is cached on-device and applied at every boot, making any non-Verizon SIM report as `CARDSTATE_RESTRICTED` (emergency calls only). This module removes the cached profile from the provisioning app's preferences at every boot, so its built-in fallback applies **all-carriers-allowed** instead.

Validated live: radio log goes from `SET_ALLOWED_CARRIERS allowed:[Verizon...] default:NOT_ALLOWED → CARDSTATE_RESTRICTED` to `SET_ALLOWED_CARRIERS allowed:[] default:ALLOWED → CARDSTATE_PRESENT`.

It does **not** modify modem firmware, EFS/NV, carrier accounts or billing.

### DeGoogleupdatetificator v1.0 (module id `noota`)
Hard-blocks automatic system (OTA) updates: disables the exact OTA components of Google Play Services (`.update.SystemUpdateService`, `.update.SystemUpdateActivity`, `.update.SystemUpdateGcmTaskService`, `.update.SystemUpdatePersistentListenerService`, `.update.OtaSuggestionActivity`, `.update.UpdateFromSdCardActivity`, `.update.UucNotificationReceiverService`), sets the `ota_disable_automatic_update` policy flag and best-effort stops `update_engine` for the current boot.

Untouched by design: GMS/Play Store themselves, Mainline (Google Play system updates), carrier OMADM, `configupdater`. **Fully reversible**: uninstalling the module restores the setting and re-enables the components.

⚠️ Blocking OTA also blocks Android security updates — you are responsible for keeping the device patched.

## Requirements

- A personally owned Pixel 6a (or compatible device) **with existing root**
- KernelSU / KernelSU-Next (or any Magisk-compatible module loader)
- A working recovery path in case something goes wrong

## Installation

From the KernelSU manager: install the release ZIP.
From a root shell:

```sh
ksud module install deverizonficator-v1.0.zip
```

Reboot. Each module writes a log into its module directory
(`/data/adb/modules/<id>/*.log`) — check it to verify what was applied.

## Removal

Uninstall via the KernelSU manager (or `ksud module uninstall <id>`).
Both modules restore the state they changed on uninstall.

## Limitations

- Tested only on the documented build; component names and preferences can change across Android builds and GMS updates.
- DeVerizonficator works because this device's lock was applied by the Android framework layer — it cannot clear a modem/NV personalization lock if one exists on other devices.
- No warranty of any kind. You use these modules at your own risk.

## Responsible use

Use only on devices you own or are authorized to administer. Respect your carrier agreement, device policy, applicable law, and Google's terms of service.

## Credits

- [KernelSU](https://kernelsu.org) / [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) — module ecosystem.
- [meta-overlayfs](https://github.com/KernelSU-Modules-Repo/meta-overlayfs) metamodule — used by the test setup during development.

## License

[GPL-3.0-or-later](LICENSE)
