[CmdletBinding()]
param(
    [string]$SdkPath,
    [switch]$CheckOnly,
    [switch]$AcceptLicenses,
    [switch]$Force,
    [switch]$RefreshDownloads
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-ToolkitConfig -RepositoryRoot $repositoryRoot
$prepareScript = Join-Path $PSScriptRoot 'Prepare-Avd.ps1'
$patchScript = Join-Path $PSScriptRoot 'Patch-Magisk.ps1'

if ($CheckOnly) {
    & $prepareScript -SdkPath $SdkPath -CheckOnly
    exit $LASTEXITCODE
}

& $prepareScript -SdkPath $SdkPath -AcceptLicenses:$AcceptLicenses -Force:$Force
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$sdkRoot = Get-AndroidSdkPath -SdkPath $SdkPath
$adb = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'adb.exe' -RelativeCandidates @('platform-tools\adb.exe')
$emulator = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'emulator.exe' -RelativeCandidates @('emulator\emulator.exe')
if (Get-AvdSerial -AdbPath $adb -AvdName $config.AvdName) {
    throw "AVD '$($config.AvdName)' is already running. Stop it and rerun Setup.cmd."
}

Write-Step -Message 'Starting the unmodified AVD for rootAVD'
Start-Process -FilePath $emulator -ArgumentList @('-avd', $config.AvdName, '-no-snapshot-load', '-no-snapshot-save')
$serial = Wait-ForAvdSerial -AdbPath $adb -AvdName $config.AvdName -TimeoutSeconds $config.BootTimeoutSeconds
Wait-ForAndroidBoot -AdbPath $adb -Serial $serial -TimeoutSeconds $config.BootTimeoutSeconds

& $patchScript -SdkPath $sdkRoot -RefreshDownloads:$RefreshDownloads
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$deadline = (Get-Date).AddSeconds(60)
do {
    Start-Sleep -Seconds 1
    $serial = Get-AvdSerial -AdbPath $adb -AvdName $config.AvdName
} while ($serial -and (Get-Date) -lt $deadline)
if ($serial) { throw 'The emulator did not shut down after rootAVD finished.' }

Write-Step -Message 'Starting the patched AVD for Magisk additional setup'
Start-Process -FilePath $emulator -ArgumentList @('-avd', $config.AvdName, '-no-snapshot-load', '-no-snapshot-save')
$serial = Wait-ForAvdSerial -AdbPath $adb -AvdName $config.AvdName -TimeoutSeconds $config.BootTimeoutSeconds
Wait-ForAndroidBoot -AdbPath $adb -Serial $serial -TimeoutSeconds $config.BootTimeoutSeconds
& $adb -s $serial shell monkey -p com.topjohnwu.magisk -c android.intent.category.LAUNCHER 1 | Out-Null

Write-Host ''
Write-Host 'In Magisk, accept "Requires additional setup" and wait for the emulator to reboot.' -ForegroundColor Yellow
Read-Host 'When Magisk shows Installed 30.7, press Enter'

$bridgeScript = Join-Path $PSScriptRoot 'Install-SuBridge.ps1'
if (Test-Path -LiteralPath $bridgeScript -PathType Leaf) {
    & $bridgeScript -SdkPath $sdkRoot
} else {
    Write-Host 'Run scripts\Install-SuBridge.ps1 after adding the bridge stage.' -ForegroundColor Yellow
}
