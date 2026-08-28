[CmdletBinding()]
param(
    [string]$SdkPath,
    [switch]$NoReboot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-ToolkitConfig -RepositoryRoot $repositoryRoot
$sdkRoot = Get-AndroidSdkPath -SdkPath $SdkPath
$adb = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'adb.exe' -RelativeCandidates @('platform-tools\adb.exe')
$serial = Get-AvdSerial -AdbPath $adb -AvdName $config.AvdName
if (-not $serial) { throw "AVD '$($config.AvdName)' is not running." }

$magiskVersion = ((& $adb -s $serial shell magisk -v) -join "`n").Trim()
if ($LASTEXITCODE -ne 0 -or -not $magiskVersion.StartsWith($config.MagiskVersion)) {
    throw "Magisk $($config.MagiskVersion) is not active on $serial. Reported: $magiskVersion"
}

$moduleSource = Join-Path $repositoryRoot 'assets\magisk-module'
$moduleProp = Join-Path $moduleSource 'module.prop'
$suBridge = Join-Path $moduleSource 'system\system_ext\bin\su'
if (-not (Test-Path -LiteralPath $moduleProp -PathType Leaf)) { throw "Missing module.prop: $moduleProp" }
if (-not (Test-Path -LiteralPath $suBridge -PathType Leaf)) { throw "Missing su bridge: $suBridge" }

$deviceStage = "/data/local/tmp/$($config.MagiskModuleId)"
$moduleTarget = "/data/adb/modules/$($config.MagiskModuleId)"
Write-Step -Message 'Staging the Magisk SU bridge'
& $adb -s $serial shell "rm -rf '$deviceStage' && mkdir -p '$deviceStage/system/system_ext/bin'"
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the device staging directory.' }
& $adb -s $serial push $moduleProp "$deviceStage/module.prop"
if ($LASTEXITCODE -ne 0) { throw 'Could not push module.prop.' }
& $adb -s $serial push $suBridge "$deviceStage/system/system_ext/bin/su"
if ($LASTEXITCODE -ne 0) { throw 'Could not push the su bridge.' }

Write-Host 'If Magisk prompts for Shell superuser access, choose Grant.' -ForegroundColor Yellow
$installCommand = "rm -rf '$moduleTarget' && mkdir -p '$moduleTarget/system/system_ext/bin' && cp '$deviceStage/module.prop' '$moduleTarget/module.prop' && cp '$deviceStage/system/system_ext/bin/su' '$moduleTarget/system/system_ext/bin/su' && chown -R 0:0 '$moduleTarget' && chmod 0755 '$moduleTarget' '$moduleTarget/system' '$moduleTarget/system/system_ext' '$moduleTarget/system/system_ext/bin' && chmod 0644 '$moduleTarget/module.prop' && chmod 0755 '$moduleTarget/system/system_ext/bin/su' && rm -rf '$deviceStage'"
& $adb -s $serial shell su -c $installCommand
if ($LASTEXITCODE -ne 0) { throw 'Magisk could not install the SU bridge module.' }

$installedId = ((& $adb -s $serial shell su -c "sed -n 's/^id=//p' '$moduleTarget/module.prop'") -join "`n").Trim()
if ($installedId -ne $config.MagiskModuleId) { throw 'Installed module id could not be verified.' }

if ($NoReboot) {
    Write-Host 'SU bridge installed. Reboot the emulator before verification.' -ForegroundColor Green
    return
}

Write-Step -Message 'Rebooting to activate the SU bridge'
& $adb -s $serial reboot
if ($LASTEXITCODE -ne 0) { throw 'ADB reboot failed.' }
$serial = Wait-ForAvdSerial -AdbPath $adb -AvdName $config.AvdName -TimeoutSeconds $config.BootTimeoutSeconds
Wait-ForAndroidBoot -AdbPath $adb -Serial $serial -TimeoutSeconds $config.BootTimeoutSeconds

$suPath = ((& $adb -s $serial shell command -v su) -join "`n").Trim()
$suVersion = ((& $adb -s $serial shell su -v) -join "`n").Trim()
if ($suPath -ne '/system_ext/bin/su') { throw "Unexpected su path after reboot: $suPath" }
if (-not $suVersion.StartsWith($config.MagiskVersion)) { throw "Unexpected MagiskSU version: $suVersion" }
Write-Host "SU bridge active at $suPath ($suVersion)." -ForegroundColor Green
