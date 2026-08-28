[CmdletBinding()]
param(
    [string]$SdkPath,
    [switch]$SkipAdbRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-ToolkitConfig -RepositoryRoot $repositoryRoot
$sdkRoot = Get-AndroidSdkPath -SdkPath $SdkPath
$adb = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'adb.exe' -RelativeCandidates @('platform-tools\adb.exe')
$emulator = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'emulator.exe' -RelativeCandidates @('emulator\emulator.exe')

$runningSerial = Get-AvdSerial -AdbPath $adb -AvdName $config.AvdName
if ($runningSerial) {
    Write-Step -Message "Stopping the existing $($config.AvdName) instance"
    & $adb -s $runningSerial emu kill | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not stop $runningSerial." }
    $deadline = (Get-Date).AddSeconds(45)
    do {
        Start-Sleep -Seconds 1
        $runningSerial = Get-AvdSerial -AdbPath $adb -AvdName $config.AvdName
    } while ($runningSerial -and (Get-Date) -lt $deadline)
    if ($runningSerial) { throw "AVD '$($config.AvdName)' did not stop within 45 seconds." }
}

Write-Step -Message "Cold booting $($config.AvdName)"
$emulatorArguments = @(
    '-avd', $config.AvdName,
    '-no-snapshot-load',
    '-no-snapshot-save'
)
Start-Process -FilePath $emulator -ArgumentList $emulatorArguments
$serial = Wait-ForAvdSerial -AdbPath $adb -AvdName $config.AvdName -TimeoutSeconds $config.BootTimeoutSeconds
Wait-ForAndroidBoot -AdbPath $adb -Serial $serial -TimeoutSeconds $config.BootTimeoutSeconds

if (-not $SkipAdbRoot) {
    Write-Step -Message "Enabling ADB root on $serial"
    & $adb -s $serial root
    if ($LASTEXITCODE -ne 0) { throw 'adb root failed.' }
    & $adb -s $serial wait-for-device | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'ADB did not reconnect after adb root.' }
}

$adbIdentity = ((& $adb -s $serial shell id) -join "`n").Trim()
if (-not $SkipAdbRoot -and -not $adbIdentity.Contains('uid=0(root)')) {
    throw "ADB shell is not root: $adbIdentity"
}
$magiskIdentity = ((& $adb -s $serial shell su -c id) -join "`n").Trim()
if (-not $magiskIdentity.Contains('uid=0(root)') -or -not $magiskIdentity.Contains('u:r:magisk:s0')) {
    throw "MagiskSU verification failed: $magiskIdentity"
}

Write-Host "Emulator ready: $serial" -ForegroundColor Green
Write-Host "ADB:    $adbIdentity"
Write-Host "Magisk: $magiskIdentity"
