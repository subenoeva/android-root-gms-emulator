# Android Root + GMS Emulator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a clean Windows Git repository that can recreate and verify an Android 16/API 36 Google APIs emulator with Magisk app-level root and cold boots.

**Architecture:** A PowerShell toolkit is split into preparation, Magisk patching, SU bridge installation, launch, verification, and recovery scripts. One declarative configuration file pins every name, version, URL, hash, and SDK package; a dependency-free test runner validates pure functions and repository contracts.

**Tech Stack:** PowerShell 5.1+, Windows batch wrappers, Android SDK command-line tools, Android Emulator, ADB, Magisk 30.7, rootAVD, Java/Android build tools for the root probe.

**Spec:** `docs/superpowers/specs/2026-08-28-android-root-gms-emulator-design.md`

## Global Constraints

- Use `Root_GMS_API_36`, API 36, `google_apis`, x86_64, Pixel 7, 2 GB RAM, and 10 GB data.
- Keep the Google system image outside Git and preserve the original ramdisk.
- Pin Magisk to v30.7 and SHA-256 `E0D32D2123532860F97123D927B1BB86C4E08E6FD8A48BFC6B5BEE0AFAE9EBD5`.
- Pin rootAVD to commit `92df40eafa2f117053f56015e3c32ca706a55fa9`.
- All launch paths must use a cold boot and target an AVD by exact name, never ambiguous `adb -e` selection.
- Do not add downloaded APKs, SDK images, generated test APKs, keystores, logs, or caches to Git.
- Commit messages and metadata must contain no automated-author attribution.
- Do not change the source Android application repository.

---

### Task 1: Repository contracts and configuration

**Files:**
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `config.psd1`
- Create: `tests/Toolkit.Tests.ps1`

**Interfaces:**
- Produces: configuration keys consumed by all scripts: `AvdName`, `ApiLevel`, `Abi`, `SourceTag`, `CustomTag`, `DeviceProfile`, `DataPartitionSize`, `RamSize`, `MagiskVersion`, `MagiskUrl`, `MagiskSha256`, `RootAvdCommit`, `RootAvdArchiveUrl`.
- Produces: a dependency-free test command, `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Toolkit.Tests.ps1`.

- [ ] **Step 1: Write the failing repository-contract test**

```powershell
$requiredFiles = @(
    'config.psd1',
    '.gitignore',
    'LICENSE'
)
foreach ($file in $requiredFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $repositoryRoot $file)) "Missing $file"
}
```

- [ ] **Step 2: Run the test and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Toolkit.Tests.ps1`

Expected: non-zero exit with `Missing config.psd1`, `.gitignore`, and `LICENSE`.

- [ ] **Step 3: Add configuration, ignore rules, and license**

```powershell
@{
    AvdName = 'Root_GMS_API_36'
    ApiLevel = 36
    Abi = 'x86_64'
    SourceTag = 'google_apis'
    CustomTag = 'google_apis_magisk'
    DeviceProfile = 'pixel_7'
    DataPartitionSize = '10G'
    RamSize = '2G'
    MagiskVersion = '30.7'
    MagiskSha256 = 'E0D32D2123532860F97123D927B1BB86C4E08E6FD8A48BFC6B5BEE0AFAE9EBD5'
    RootAvdCommit = '92df40eafa2f117053f56015e3c32ca706a55fa9'
}
```

- [ ] **Step 4: Run the test and verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Toolkit.Tests.ps1`

Expected: configuration and repository-contract assertions pass with exit code 0.

- [ ] **Step 5: Commit the repository foundation**

```powershell
git add .gitignore LICENSE config.psd1 tests/Toolkit.Tests.ps1 docs
git commit -m "chore: define emulator toolkit contract"
```

### Task 2: Shared PowerShell functions

**Files:**
- Create: `scripts/Common.ps1`
- Modify: `tests/Toolkit.Tests.ps1`

**Interfaces:**
- Produces: `Get-ToolkitConfig`, `Get-AndroidSdkPath`, `Resolve-ContainedPath`, `Get-AvdSerial`, `Wait-ForAndroidBoot`, `Invoke-CheckedProcess`, and `Get-Sha256`.
- Consumes: `config.psd1` from Task 1.

- [ ] **Step 1: Add failing tests for path containment and configuration**

```powershell
. (Join-Path $repositoryRoot 'scripts/Common.ps1')
$base = Join-Path ([System.IO.Path]::GetTempPath()) 'toolkit-test-root'
$inside = Resolve-ContainedPath -BasePath $base -ChildPath 'cache/file.zip'
Assert-True ($inside.StartsWith([System.IO.Path]::GetFullPath($base))) 'Contained path was rejected'
Assert-Throws { Resolve-ContainedPath -BasePath $base -ChildPath '..\outside.txt' } 'Escaping path was accepted'
```

- [ ] **Step 2: Run the test and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Toolkit.Tests.ps1`

Expected: failure because `scripts/Common.ps1` or `Resolve-ContainedPath` does not exist.

- [ ] **Step 3: Implement the minimal shared functions**

```powershell
function Resolve-ContainedPath {
    param([string]$BasePath, [string]$ChildPath)
    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\')
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $base $ChildPath))
    if (-not $candidate.StartsWith($base + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes base directory: $candidate"
    }
    $candidate
}
```

- [ ] **Step 4: Run tests and verify GREEN for shared functions**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Toolkit.Tests.ps1`

Expected: pure-function tests pass; later missing-file contracts remain RED.

- [ ] **Step 5: Commit shared functions**

```powershell
git add scripts/Common.ps1 tests/Toolkit.Tests.ps1
git commit -m "feat: add shared Android tooling functions"
```

### Task 3: AVD preparation and Magisk patching

**Files:**
- Create: `scripts/Prepare-Avd.ps1`
- Create: `scripts/Patch-Magisk.ps1`
- Create: `scripts/Setup.ps1`
- Create: `Setup.cmd`
- Create: `scripts/Restore-OriginalRamdisk.ps1`
- Modify: `tests/Toolkit.Tests.ps1`

**Interfaces:**
- `Prepare-Avd.ps1 -CheckOnly` reports prerequisites and existing state without mutation.
- `Prepare-Avd.ps1` installs/checks SDK packages, creates the source AVD, copies the system image, and records hashes.
- `Patch-Magisk.ps1` downloads pinned inputs, verifies Magisk, runs rootAVD, and switches `image.sysdir.1` only after patch validation.
- `Setup.ps1` calls the stages in order and stops at the documented Magisk UI checkpoint.
- `Restore-OriginalRamdisk.ps1` restores only the isolated ramdisk backup after explicit confirmation.

- [ ] **Step 1: Add failing static and check-only tests**

```powershell
Assert-FileContains 'scripts/Prepare-Avd.ps1' '-CheckOnly'
Assert-FileContains 'scripts/Patch-Magisk.ps1' 'MagiskSha256'
Assert-FileContains 'scripts/Patch-Magisk.ps1' 'ramdisk.img.backup'
Assert-FileContains 'scripts/Restore-OriginalRamdisk.ps1' 'ShouldProcess'
```

- [ ] **Step 2: Run the test and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Toolkit.Tests.ps1`

Expected: failure naming the missing setup scripts.

- [ ] **Step 3: Implement preparation and patch orchestration**

```powershell
$sourcePackage = "system-images;android-$($config.ApiLevel);$($config.SourceTag);$($config.Abi)"
& $sdkManager $sourcePackage 'platform-tools' 'emulator'
if ($LASTEXITCODE -ne 0) { throw 'Android SDK package installation failed.' }
& $avdManager create avd -n $config.AvdName -k $sourcePackage -d $config.DeviceProfile
if ($LASTEXITCODE -ne 0) { throw 'AVD creation failed.' }
```

The implementation must refuse an existing target unless `-Force` is supplied, copy the full source image before patching, and compare source/backup hashes before continuing.

- [ ] **Step 4: Run static tests and non-destructive prerequisite check**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Toolkit.Tests.ps1`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Prepare-Avd.ps1 -CheckOnly`

Expected: tests pass through Task 3 and check-only reports the current SDK/AVD without modifying it.

- [ ] **Step 5: Commit setup and recovery**

```powershell
git add Setup.cmd scripts/Prepare-Avd.ps1 scripts/Patch-Magisk.ps1 scripts/Setup.ps1 scripts/Restore-OriginalRamdisk.ps1 tests/Toolkit.Tests.ps1
git commit -m "feat: automate AVD and Magisk preparation"
```

### Task 4: SU bridge, cold-boot launcher, and runtime verification

**Files:**
- Create: `assets/magisk-module/module.prop`
- Create: `assets/magisk-module/system/system_ext/bin/su`
- Create: `scripts/Install-SuBridge.ps1`
- Create: `scripts/Launch-Cold-Boot.ps1`
- Create: `Launch-Cold-Boot.cmd`
- Create: `scripts/Verify-Emulator.ps1`
- Modify: `tests/Toolkit.Tests.ps1`

**Interfaces:**
- `Install-SuBridge.ps1` installs `avd_magisk_su_bridge` under `/data/adb/modules` and reboots.
- `Launch-Cold-Boot.ps1` always uses `-no-snapshot-load -no-snapshot-save` and resolves the exact AVD serial.
- `Verify-Emulator.ps1` returns non-zero unless Magisk, MagiskSU, UID 0, GMS, GSF, and network all pass.

- [ ] **Step 1: Add failing launcher and module tests**

```powershell
Assert-FileContains 'scripts/Launch-Cold-Boot.ps1' '-no-snapshot-load'
Assert-FileContains 'scripts/Launch-Cold-Boot.ps1' '-no-snapshot-save'
Assert-FileContains 'assets/magisk-module/system/system_ext/bin/su' 'exec /debug_ramdisk/su "$@"'
Assert-FileContains 'scripts/Verify-Emulator.ps1' 'com.google.android.gms'
```

- [ ] **Step 2: Run the test and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Toolkit.Tests.ps1`

Expected: failure naming the missing launcher, module, and verifier.

- [ ] **Step 3: Implement module installation, launch, and verification**

```powershell
$arguments = @('-avd', $config.AvdName, '-no-snapshot-load', '-no-snapshot-save')
Start-Process -FilePath $emulator -ArgumentList $arguments
$serial = Wait-ForAvdSerial -AdbPath $adb -AvdName $config.AvdName -TimeoutSeconds 300
Wait-ForAndroidBoot -AdbPath $adb -Serial $serial -TimeoutSeconds 300
```

The installer pushes the module to a temporary device path, copies it into `/data/adb/modules/avd_magisk_su_bridge` through MagiskSU, sets directories to 0755 and files to 0644/0755, and verifies `/system_ext/bin/su` after reboot.

- [ ] **Step 4: Run tests and runtime verification on the existing AVD**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Toolkit.Tests.ps1`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Verify-Emulator.ps1`

Expected: static suite exits 0; runtime output includes Magisk 30.7, MagiskSU 30.7, `uid=0(root)`, GMS, GSF, and successful network resolution.

- [ ] **Step 5: Commit launch and verification tooling**

```powershell
git add Launch-Cold-Boot.cmd assets scripts/Install-SuBridge.ps1 scripts/Launch-Cold-Boot.ps1 scripts/Verify-Emulator.ps1 tests/Toolkit.Tests.ps1
git commit -m "feat: add cold boot and root verification"
```

### Task 5: App-level root probe and operator documentation

**Files:**
- Create: `tests/root-probe/AndroidManifest.xml`
- Create: `tests/root-probe/RootProbeActivity.java`
- Create: `tests/root-probe/Build-And-Run.ps1`
- Create: `scripts/Verify-Toolkit.ps1`
- Create: `README.md`
- Create: `docs/troubleshooting.md`
- Modify: `tests/Toolkit.Tests.ps1`

**Interfaces:**
- `tests/root-probe/Build-And-Run.ps1` builds, signs, installs, launches, checks, and uninstalls `com.example.rootprobe`.
- `scripts/Verify-Toolkit.ps1` parses every PowerShell file and calls the dependency-free contract suite.
- `README.md` is the complete Spanish operator guide.

- [ ] **Step 1: Add failing documentation and root-probe tests**

```powershell
Assert-FileContains 'tests/root-probe/RootProbeActivity.java' 'new ProcessBuilder("su", "-c", "id")'
Assert-FileContains 'tests/root-probe/Build-And-Run.ps1' 'com.example.rootprobe'
Assert-FileContains 'README.md' 'Instalación desde cero'
Assert-FileContains 'docs/troubleshooting.md' 'Permission denied'
```

- [ ] **Step 2: Run the test and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/Toolkit.Tests.ps1`

Expected: failure naming the missing probe and documentation.

- [ ] **Step 3: Implement the probe, toolkit verifier, and documentation**

```java
Process process = new ProcessBuilder("su", "-c", "id")
        .redirectErrorStream(true)
        .start();
int exitCode = process.waitFor();
String output = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
result.setText("exit=" + exitCode + "\n" + output);
```

The README must give exact commands for prerequisites, setup stages, Magisk UI interaction, verification, cold boot, restoration, and updates. Troubleshooting must explain ambiguous ADB selection, file-picker timeout, shadowed AOSP `su`, and custom-image AVD warnings.

- [ ] **Step 4: Run all static and live tests**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Verify-Toolkit.ps1`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Verify-Emulator.ps1`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tests/root-probe/Build-And-Run.ps1`

Expected: all commands exit 0; the probe reports `exit=0` and `uid=0(root)` before uninstalling itself.

- [ ] **Step 5: Check repository cleanliness and commit documentation**

```powershell
git status --short
$forbidden = @(('co' + 'dex'), ('open' + 'ai'), ('chat' + 'gpt'), ('co-' + 'authored-by'), ('generated by ' + 'ai'))
git grep -inE ($forbidden -join '|')
git add README.md docs scripts/Verify-Toolkit.ps1 tests
git commit -m "docs: add reproducible root emulator guide"
git status --short --branch
```

Expected: attribution search has no matches, commit succeeds with the configured human Git identity, and the worktree is clean.
