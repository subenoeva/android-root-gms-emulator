[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([string]$SdkPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-ToolkitConfig -RepositoryRoot $repositoryRoot
$sdkRoot = Get-AndroidSdkPath -SdkPath $SdkPath
$adb = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'adb.exe' -RelativeCandidates @('platform-tools\adb.exe')

if (Get-AvdSerial -AdbPath $adb -AvdName $config.AvdName) {
    throw "Stop AVD '$($config.AvdName)' before restoring its ramdisk."
}

$systemImagesRoot = Join-Path $sdkRoot 'system-images'
$relativeRamdisk = "android-$($config.ApiLevel)\$($config.CustomTag)\$($config.Abi)\ramdisk.img"
$ramdisk = Resolve-ContainedPath -BasePath $systemImagesRoot -ChildPath $relativeRamdisk
$backup = "$ramdisk.backup"
if (-not (Test-Path -LiteralPath $ramdisk -PathType Leaf)) { throw "Ramdisk not found: $ramdisk" }
if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw "Ramdisk backup not found: $backup" }

if ($PSCmdlet.ShouldProcess($ramdisk, "Restore $backup")) {
    $patchedCopy = "$ramdisk.patched-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $ramdisk -Destination $patchedCopy
    Copy-Item -LiteralPath $backup -Destination $ramdisk -Force
    if ((Get-Sha256 -Path $ramdisk) -ne (Get-Sha256 -Path $backup)) {
        throw 'Restored ramdisk hash does not match the backup.'
    }
    Write-Host "Original ramdisk restored. Patched copy kept at $patchedCopy" -ForegroundColor Green
}
