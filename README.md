# Android Root + GMS Emulator

A reproducible toolkit for creating an Android Virtual Device on Windows with:

- Android 16 / API 36, x86_64.
- A Google APIs image with Google Play Services and Google Services Framework.
- Magisk 30.7 and root access for applications.
- A cold boot on every launch.
- The original Google image left intact and a backup of the ramdisk.

This toolkit does not use a `google_apis_playstore` image. Play Store images are signed for production and do not allow elevated privileges. The `google_apis` variant includes the required Google services, but not the Play Store application.

## Pinned configuration

All values are centralized in [`config.psd1`](config.psd1):

| Component | Value |
|---|---|
| AVD | `Root_GMS_API_36` |
| Android | API 36 / x86_64 |
| Device profile | Pixel 7 |
| Original image | `google_apis` |
| Patched copy | `google_apis_magisk` |
| Magisk | 30.7 |
| Android Build Tools | 36.0.0 |
| rootAVD | commit `92df40eafa2f117053f56015e3c32ca706a55fa9` |

The Magisk APK is accepted only when its SHA-256 is:

```text
E0D32D2123532860F97123D927B1BB86C4E08E6FD8A48BFC6B5BEE0AFAE9EBD5
```

## Requirements

- 64-bit Windows 10 or 11 with virtualization enabled.
- Android Studio or the Android SDK Command-Line Tools.
- Git for Windows, including Git Bash, which is required by `rootAVD.bat`.
- JDK 17 or newer. Android Studio includes a compatible JDK under `jbr`.
- PowerShell 5.1 or newer.
- At least 12 GB of free space on the SDK drive.
- An Internet connection during setup.

The SDK is located in this order:

1. The `-SdkPath` parameter.
2. `ANDROID_SDK_ROOT`.
3. `ANDROID_HOME`.
4. `%LOCALAPPDATA%\Android\Sdk`.

## Installation from scratch

Open PowerShell in the repository directory.

### 1. Check the environment

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Prepare-Avd.ps1 -CheckOnly
```

This mode does not modify any files. It must locate `sdkmanager`, `avdmanager`, ADB, and the emulator.

### 2. Run the full setup

If the SDK licenses have already been accepted through Android Studio:

```powershell
.\Setup.cmd
```

To accept the licenses from the script:

```powershell
.\Setup.cmd -AcceptLicenses
```

The setup installs or checks the following packages:

```text
platform-tools
emulator
platforms;android-36
build-tools;36.0.0
system-images;android-36;google_apis;x86_64
```

It then creates `Root_GMS_API_36` and copies the system image:

```text
Original: system-images\android-36\google_apis\x86_64
Copy:     system-images\android-36\google_apis_magisk\x86_64
```

The original image is not modified.

If an AVD or isolated copy already exists with those names, the script stops. `-Force` does not delete them: it moves them to paths with a `.pre-toolkit-yyyyMMdd-HHmmss` suffix before creating the new environment.

### 3. Patch the ramdisk with Magisk

`Setup.cmd` launches the original AVD and runs the pinned rootAVD commit. Magisk opens inside the emulator.

1. If the Magisk home screen appears, select `Install` next to Magisk.
2. Select `Select and Patch a File`.
3. Open `Downloads` and select `fakeboot.img`.
4. Select `LET'S GO`.
5. Wait until `All done` appears.
6. Return to the terminal and press Enter before the 300-second timeout expires.

The script continues only when all three conditions are met:

- `ramdisk.img.backup` exists.
- Its hash matches the ramdisk from before the patch.
- The active ramdisk hash has changed.

The script then changes `image.sysdir.1` so the AVD uses the isolated copy.

### 4. Complete the Magisk installation

The AVD starts again with a cold boot and Magisk opens.

1. Accept `Requires additional setup`.
2. Allow Magisk to restart the emulator.
3. Wait until the home screen shows `Installed 30.7`.
4. Return to the terminal and press Enter.

### 5. Install the `su` bridge

The setup automatically runs:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-SuBridge.ps1
```

If Magisk asks for superuser access for `Shell`, select `Grant`.

The Google APIs image contains `/system/xbin/su`, but that binary is restricted to `root:shell` and can hide MagiskSU from applications. The included module mounts `/system_ext/bin/su`, which delegates to:

```sh
/debug_ramdisk/su
```

After the restart, `command -v su` must return `/system_ext/bin/su`.

## Verification

### Verify the repository

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Verify-Toolkit.ps1
```

This checks syntax, repository contracts, module line endings, the absence of downloaded binaries in Git, and clean commit attribution.

### Verify the emulator

With the AVD running:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Verify-Emulator.ps1
```

The script checks:

- `sys.boot_completed=1`.
- The exact AVD name.
- Magisk `30.7:MAGISK:R`.
- MagiskSU `30.7:MAGISKSU`.
- `su -c id` returns `uid=0(root)` with the `u:r:magisk:s0` context.
- The Google Play Services APK.
- The Google Services Framework APK.
- Network connectivity.

### Prove root access from an application

The previous check uses the `shell` UID. To prove that a regular application can obtain root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\root-probe\Build-And-Run.ps1
```

The script builds and signs a temporary APK without Gradle, installs it, and opens it. Grant the request in Magisk. If no dialog appears, open `Magisk > Superuser`, enable `Root Probe`, reopen the probe, and press Enter in the terminal. The test requires:

```text
exit=0
uid=0(root)
```

It also checks that the package was running under a normal Android application UID of 10000 or higher. When finished, it uninstalls the APK and removes its artifacts. Use `-KeepArtifacts` only when you need to inspect them.

## Launching with a cold boot

Double-click:

```text
Launch-Cold-Boot.cmd
```

Or run it from PowerShell:

```powershell
.\Launch-Cold-Boot.cmd
```

The launcher:

1. Stops only an active `Root_GMS_API_36` instance.
2. Runs the emulator with `-no-snapshot-load -no-snapshot-save`.
3. Resolves the serial by querying the AVD name, even when a physical phone is connected.
4. Waits for the boot to complete.
5. Enables `adb root` for that exact serial.
6. Verifies MagiskSU.

It does not use `adb -e`, so the target remains unambiguous when ADB detects multiple devices.

## Restoring the original ramdisk

Close the AVD and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-OriginalRamdisk.ps1 -Confirm
```

The script first preserves another copy of the patched ramdisk and then restores `ramdisk.img.backup`. It verifies the hashes before completing.

This removes Magisk from the isolated ramdisk. It does not modify the original image downloaded by `sdkmanager`.

## Updating Magisk or rootAVD

Do not manually replace downloaded files inside `.cache`.

1. Update the version, URL, and hash in `config.psd1`.
2. Update the pinned rootAVD commit and URL when required.
3. Check whether the timeout block in `rootAVD.sh` is still identical.
4. Run the static checks.
5. Prepare a new AVD or restore the ramdisk before patching it again.
6. Use `-RefreshDownloads` to rebuild the cache:

```powershell
.\Setup.cmd -RefreshDownloads
```

The script stops if the Magisk hash does not match or if the pinned rootAVD source no longer contains the reviewed block.

## Main files

| File | Responsibility |
|---|---|
| `config.psd1` | Versions, names, URLs, and hashes |
| `Setup.cmd` | Entry point for the full installation |
| `scripts/Prepare-Avd.ps1` | SDK, AVD, and isolated image copy |
| `scripts/Patch-Magisk.ps1` | Verified download and rootAVD patch |
| `scripts/Install-SuBridge.ps1` | Module that exposes MagiskSU to applications |
| `Launch-Cold-Boot.cmd` | Daily cold-boot launcher |
| `scripts/Verify-Emulator.ps1` | Runtime verification |
| `tests/root-probe/Build-And-Run.ps1` | Verification from an application UID |
| `scripts/Restore-OriginalRamdisk.ps1` | Reversible recovery |
| `docs/troubleshooting.md` | Troubleshooting known failures |

## Sources

- [Create and manage virtual devices](https://developer.android.com/studio/run/managing-avds)
- [Start the emulator from the command line](https://developer.android.com/studio/run/emulator-commandline)
- [avdmanager](https://developer.android.com/tools/avdmanager)
- [Magisk](https://github.com/topjohnwu/Magisk)
- [rootAVD](https://github.com/galihlasahido/rootAVD)

Magisk and rootAVD retain their own licenses and terms. This repository does not redistribute their artifacts or Google system images.
