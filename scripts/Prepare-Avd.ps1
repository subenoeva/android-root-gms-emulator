[CmdletBinding()]
param(
    [string]$SdkPath,
    [switch]$CheckOnly,
    [switch]$AcceptLicenses,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-ToolkitConfig -RepositoryRoot $repositoryRoot
$sdkRoot = Get-AndroidSdkPath -SdkPath $SdkPath
$sdkManager = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'sdkmanager.bat' -RelativeCandidates @(
    'cmdline-tools\latest\bin\sdkmanager.bat',
    'cmdline-tools\bin\sdkmanager.bat'
)
$avdManager = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'avdmanager.bat' -RelativeCandidates @(
    'cmdline-tools\latest\bin\avdmanager.bat',
    'cmdline-tools\bin\avdmanager.bat'
)
$adb = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'adb.exe' -RelativeCandidates @('platform-tools\adb.exe')
$emulator = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'emulator.exe' -RelativeCandidates @('emulator\emulator.exe')

$sourcePackage = "system-images;android-$($config.ApiLevel);$($config.SourceTag);$($config.Abi)"
$sourceRelativePath = "system-images\android-$($config.ApiLevel)\$($config.SourceTag)\$($config.Abi)"
$customRelativePath = "system-images\android-$($config.ApiLevel)\$($config.CustomTag)\$($config.Abi)"
$sourceImageDirectory = Join-Path $sdkRoot $sourceRelativePath
$customImageDirectory = Join-Path $sdkRoot $customRelativePath
$avdHome = Get-AvdHome
$avdDirectory = Join-Path $avdHome "$($config.AvdName).avd"
$avdIni = Join-Path $avdHome "$($config.AvdName).ini"

Write-Step -Message 'Checking prerequisites'
Write-Host "SDK: $sdkRoot"
Write-Host "AVD: $($config.AvdName)"
Write-Host "Source package: $sourcePackage"
Write-Host "Source image installed: $(Test-Path -LiteralPath $sourceImageDirectory -PathType Container)"
Write-Host "Isolated image present: $(Test-Path -LiteralPath $customImageDirectory -PathType Container)"
Write-Host "AVD present: $((Test-Path -LiteralPath $avdDirectory -PathType Container) -and (Test-Path -LiteralPath $avdIni -PathType Leaf))"
Write-Host "ADB: $adb"
Write-Host "Emulator: $emulator"

if ($CheckOnly) {
    Write-Host 'Check-only completed. No files were changed.' -ForegroundColor Green
    return
}

Assert-FreeSpace -Path $sdkRoot -MinimumGigabytes $config.MinimumFreeSpaceGb | Out-Null

if ($AcceptLicenses) {
    Write-Step -Message 'Accepting Android SDK licenses'
    $licenseCommand = "(for /l %i in (1,1,30) do @echo y) | `"$sdkManager`" --licenses"
    Invoke-CheckedProcess -FilePath $env:ComSpec -ArgumentList @('/d', '/s', '/c', $licenseCommand) | Out-Null
}

Write-Step -Message 'Installing required Android SDK packages'
Invoke-CheckedProcess -FilePath $sdkManager -ArgumentList @(
    '--install',
    'platform-tools',
    'emulator',
    $sourcePackage
) | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ((Test-Path -LiteralPath $avdDirectory) -or (Test-Path -LiteralPath $avdIni)) {
    if (-not $Force) {
        throw "AVD '$($config.AvdName)' already exists. Use -CheckOnly to inspect it or -Force to move it to a timestamped backup."
    }
    if (Get-AvdSerial -AdbPath $adb -AvdName $config.AvdName) {
        throw "AVD '$($config.AvdName)' is running. Stop it before using -Force."
    }
    if (Test-Path -LiteralPath $avdDirectory) {
        Move-Item -LiteralPath $avdDirectory -Destination "$avdDirectory.pre-toolkit-$timestamp"
    }
    if (Test-Path -LiteralPath $avdIni) {
        Move-Item -LiteralPath $avdIni -Destination "$avdIni.pre-toolkit-$timestamp"
    }
}

if (Test-Path -LiteralPath $customImageDirectory) {
    if (-not $Force) {
        throw "Isolated image already exists: $customImageDirectory. Use -Force to move it to a timestamped backup."
    }
    Move-Item -LiteralPath $customImageDirectory -Destination "$customImageDirectory.pre-toolkit-$timestamp"
}

Write-Step -Message 'Creating the AVD against the original Google APIs image'
New-Item -ItemType Directory -Path $avdHome -Force | Out-Null
$createCommand = "echo no | `"$avdManager`" create avd -n `"$($config.AvdName)`" -k `"$sourcePackage`" -d `"$($config.DeviceProfile)`" -c 512M"
Invoke-CheckedProcess -FilePath $env:ComSpec -ArgumentList @('/d', '/s', '/c', $createCommand) | Out-Null

$avdConfig = Join-Path $avdDirectory 'config.ini'
Set-IniValue -Path $avdConfig -Key 'disk.dataPartition.size' -Value $config.DataPartitionSize
Set-IniValue -Path $avdConfig -Key 'hw.ramSize' -Value $config.RamSize
Set-IniValue -Path $avdConfig -Key 'PlayStore.enabled' -Value 'no'

if (-not (Test-Path -LiteralPath $sourceImageDirectory -PathType Container)) {
    throw "The installed package did not create the expected image directory: $sourceImageDirectory"
}
$sourceRamdisk = Join-Path $sourceImageDirectory 'ramdisk.img'
if (-not (Test-Path -LiteralPath $sourceRamdisk -PathType Leaf)) { throw "Source ramdisk not found: $sourceRamdisk" }

Write-Step -Message 'Creating the isolated image copy'
New-Item -ItemType Directory -Path (Split-Path -Parent $customImageDirectory) -Force | Out-Null
Copy-Item -LiteralPath $sourceImageDirectory -Destination $customImageDirectory -Recurse
$customRamdisk = Join-Path $customImageDirectory 'ramdisk.img'
$sourceHash = Get-Sha256 -Path $sourceRamdisk
$customHash = Get-Sha256 -Path $customRamdisk
if ($sourceHash -ne $customHash) { throw 'The isolated ramdisk does not match the original copy.' }

$cacheDirectory = Resolve-ContainedPath -BasePath $repositoryRoot -ChildPath '.cache'
New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
$state = [ordered]@{
    createdAt = (Get-Date).ToString('o')
    sdkRoot = $sdkRoot
    avdName = $config.AvdName
    sourceImageDirectory = $sourceImageDirectory
    customImageDirectory = $customImageDirectory
    originalRamdiskSha256 = $sourceHash
}
$state | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $cacheDirectory 'prepare-state.json') -Encoding UTF8

Write-Host 'AVD and isolated image prepared successfully.' -ForegroundColor Green
Write-Host "Original ramdisk SHA-256: $sourceHash"
