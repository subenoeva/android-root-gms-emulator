[CmdletBinding()]
param([string]$SdkPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-ToolkitConfig -RepositoryRoot $repositoryRoot
$sdkRoot = Get-AndroidSdkPath -SdkPath $SdkPath
$adb = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'adb.exe' -RelativeCandidates @('platform-tools\adb.exe')
$serial = Get-AvdSerial -AdbPath $adb -AvdName $config.AvdName
if (-not $serial) { throw "AVD '$($config.AvdName)' is not running." }

function Invoke-AdbText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = & $adb -s $serial @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB command failed: adb -s $serial $($Arguments -join ' ')`n$($output -join "`n")" }
    ($output -join "`n").Trim()
}

Write-Step -Message "Verifying $($config.AvdName) on $serial"
$bootCompleted = Invoke-AdbText -Arguments @('shell', 'getprop', 'sys.boot_completed')
if ($bootCompleted -ne '1') { throw "Android boot is incomplete: $bootCompleted" }

$reportedName = Invoke-AdbText -Arguments @('emu', 'avd', 'name')
$reportedName = (($reportedName -split "`n") | Where-Object { $_.Trim() -and $_.Trim() -ne 'OK' } | Select-Object -First 1).Trim()
if ($reportedName -ne $config.AvdName) { throw "Unexpected AVD name: $reportedName" }

$magiskVersion = Invoke-AdbText -Arguments @('shell', 'magisk', '-v')
$expectedMagisk = "$($config.MagiskVersion):MAGISK:R"
if ($magiskVersion -ne $expectedMagisk) { throw "Unexpected Magisk version: $magiskVersion" }

$suVersion = Invoke-AdbText -Arguments @('shell', 'su', '-v')
$expectedSu = "$($config.MagiskVersion):MAGISKSU"
if ($suVersion -ne $expectedSu) { throw "Unexpected MagiskSU version: $suVersion" }

$suPath = Invoke-AdbText -Arguments @('shell', 'command', '-v', 'su')
if ($suPath -ne '/system_ext/bin/su') { throw "Unexpected su path: $suPath" }

$rootIdentity = Invoke-AdbText -Arguments @('shell', 'su', '-c', 'id')
if (-not $rootIdentity.Contains('uid=0(root)') -or -not $rootIdentity.Contains('u:r:magisk:s0')) {
    throw "MagiskSU did not produce the expected identity: $rootIdentity"
}

$gmsPath = Invoke-AdbText -Arguments @('shell', 'pm', 'path', $config.GooglePlayServicesPackage)
if (-not $gmsPath.StartsWith('package:')) { throw 'Google Play Services APK was not found.' }
$gsfPath = Invoke-AdbText -Arguments @('shell', 'pm', 'path', $config.GoogleServicesFrameworkPackage)
if (-not $gsfPath.StartsWith('package:')) { throw 'Google Services Framework APK was not found.' }

$networkOk = $false
for ($attempt = 1; $attempt -le 10; $attempt++) {
    & $adb -s $serial shell ping -c 1 -W 3 google.com *> $null
    if ($LASTEXITCODE -eq 0) {
        $networkOk = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $networkOk) { throw 'Network verification failed after ten attempts.' }

Write-Host 'Runtime verification passed.' -ForegroundColor Green
Write-Host "AVD:      $reportedName ($serial)"
Write-Host "Magisk:   $magiskVersion"
Write-Host "MagiskSU: $suVersion at $suPath"
Write-Host "Root:     $rootIdentity"
Write-Host "GMS:      $gmsPath"
Write-Host "GSF:      $gsfPath"
Write-Host 'Network:  OK'
