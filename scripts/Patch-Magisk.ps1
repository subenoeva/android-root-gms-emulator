[CmdletBinding()]
param(
    [string]$SdkPath,
    [switch]$RefreshDownloads
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-ToolkitConfig -RepositoryRoot $repositoryRoot
$sdkRoot = Get-AndroidSdkPath -SdkPath $SdkPath
$adb = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'adb.exe' -RelativeCandidates @('platform-tools\adb.exe')
$cacheDirectory = Resolve-ContainedPath -BasePath $repositoryRoot -ChildPath '.cache'
$downloadDirectory = Resolve-ContainedPath -BasePath $cacheDirectory -ChildPath 'downloads'
$toolsDirectory = Resolve-ContainedPath -BasePath $cacheDirectory -ChildPath 'tools'
New-Item -ItemType Directory -Path $downloadDirectory, $toolsDirectory -Force | Out-Null

$magiskApk = Resolve-ContainedPath -BasePath $downloadDirectory -ChildPath "Magisk-v$($config.MagiskVersion).apk"
$rootAvdArchive = Resolve-ContainedPath -BasePath $downloadDirectory -ChildPath "rootAVD-$($config.RootAvdCommit).zip"
$rootAvdDirectory = Resolve-ContainedPath -BasePath $toolsDirectory -ChildPath "rootAVD-$($config.RootAvdCommit)"

if ($RefreshDownloads) {
    foreach ($path in @($magiskApk, $rootAvdArchive, $rootAvdDirectory)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if (-not (Test-Path -LiteralPath $magiskApk -PathType Leaf)) {
    Write-Step -Message "Downloading Magisk $($config.MagiskVersion)"
    Invoke-WebRequest -UseBasicParsing -Uri $config.MagiskUrl -OutFile $magiskApk
}
$magiskHash = Get-Sha256 -Path $magiskApk
if ($magiskHash -ne $config.MagiskSha256) {
    throw "Magisk SHA-256 mismatch. Expected $($config.MagiskSha256), got $magiskHash."
}

if (-not (Test-Path -LiteralPath $rootAvdArchive -PathType Leaf)) {
    Write-Step -Message "Downloading rootAVD commit $($config.RootAvdCommit)"
    Invoke-WebRequest -UseBasicParsing -Uri $config.RootAvdArchiveUrl -OutFile $rootAvdArchive
}
if (-not (Test-Path -LiteralPath $rootAvdDirectory -PathType Container)) {
    Expand-Archive -LiteralPath $rootAvdArchive -DestinationPath $toolsDirectory
}
if (-not (Test-Path -LiteralPath (Join-Path $rootAvdDirectory 'rootAVD.bat') -PathType Leaf)) {
    throw "Pinned rootAVD archive has an unexpected layout: $rootAvdDirectory"
}

$rootAvdScript = Join-Path $rootAvdDirectory 'rootAVD.sh'
$scriptContent = Get-Content -LiteralPath $rootAvdScript -Raw
$oldPrompt = 'echo "[*] Install/Patch $FBI and hit Enter when done(max. 60s)"'
$oldRead = 'read -t 60 proceed'
$newPrompt = "echo `"[*] Install/Patch `$FBI and hit Enter when done(max. $($config.RootAvdUiTimeoutSeconds)s)`""
$newRead = "read -t $($config.RootAvdUiTimeoutSeconds) proceed"
if ($scriptContent.Contains($oldPrompt) -and $scriptContent.Contains($oldRead)) {
    $scriptContent = $scriptContent.Replace($oldPrompt, $newPrompt).Replace($oldRead, $newRead)
    [System.IO.File]::WriteAllText($rootAvdScript, $scriptContent, (New-Object System.Text.UTF8Encoding($false)))
} elseif ($scriptContent.Contains($newPrompt) -and $scriptContent.Contains($newRead)) {
    Write-Host 'rootAVD already contains the reviewed UI timeout patch.'
} else {
    throw 'The pinned rootAVD timeout block no longer matches the reviewed source.'
}
Copy-Item -LiteralPath $magiskApk -Destination (Join-Path $rootAvdDirectory 'Magisk.zip') -Force
Copy-Item -LiteralPath $magiskApk -Destination (Join-Path $rootAvdDirectory 'Magisk30.zip') -Force

$customRelativePath = "system-images\android-$($config.ApiLevel)\$($config.CustomTag)\$($config.Abi)"
$customImageDirectory = Join-Path $sdkRoot $customRelativePath
$ramdisk = Join-Path $customImageDirectory 'ramdisk.img'
$ramdiskBackup = "$ramdisk.backup"
if (-not (Test-Path -LiteralPath $ramdisk -PathType Leaf)) { throw "Isolated ramdisk not found: $ramdisk" }
if (Test-Path -LiteralPath $ramdiskBackup -PathType Leaf) {
    throw "A ramdisk backup already exists. Refusing to patch again: $ramdiskBackup"
}
$beforeHash = Get-Sha256 -Path $ramdisk

$serial = Get-AvdSerial -AdbPath $adb -AvdName $config.AvdName
if (-not $serial) {
    throw "Start AVD '$($config.AvdName)' against the original image before running this script."
}

Write-Host ''
Write-Host 'Magisk will open a file picker inside the emulator.' -ForegroundColor Yellow
Write-Host 'Choose /sdcard/Download/fakeboot.img, press LET''S GO, wait for All done, then return to this terminal.' -ForegroundColor Yellow
Read-Host 'Press Enter to start rootAVD'

$oldAndroidHome = $env:ANDROID_HOME
$oldAndroidSdkRoot = $env:ANDROID_SDK_ROOT
$oldAndroidSerial = $env:ANDROID_SERIAL
$oldPath = $env:PATH
try {
    $env:ANDROID_HOME = $sdkRoot
    $env:ANDROID_SDK_ROOT = $sdkRoot
    $env:ANDROID_SERIAL = $serial
    $env:PATH = "$(Join-Path $sdkRoot 'platform-tools');$oldPath"
    $targetRamdisk = "$customRelativePath\ramdisk.img"
    Invoke-CheckedProcess -FilePath (Join-Path $rootAvdDirectory 'rootAVD.bat') -ArgumentList @($targetRamdisk, 'FAKEBOOTIMG') -WorkingDirectory $rootAvdDirectory | Out-Null
} finally {
    $env:ANDROID_HOME = $oldAndroidHome
    $env:ANDROID_SDK_ROOT = $oldAndroidSdkRoot
    $env:ANDROID_SERIAL = $oldAndroidSerial
    $env:PATH = $oldPath
}

if (-not (Test-Path -LiteralPath $ramdiskBackup -PathType Leaf)) { throw 'rootAVD did not create ramdisk.img.backup.' }
$backupHash = Get-Sha256 -Path $ramdiskBackup
$patchedHash = Get-Sha256 -Path $ramdisk
if ($backupHash -ne $beforeHash) { throw 'The ramdisk backup does not match the pre-patch image.' }
if ($patchedHash -eq $beforeHash) { throw 'The ramdisk hash did not change; Magisk patching was not completed.' }

$avdConfig = Join-Path (Join-Path (Get-AvdHome) "$($config.AvdName).avd") 'config.ini'
$avdConfigBackup = "$avdConfig.pre-magisk"
if (-not (Test-Path -LiteralPath $avdConfigBackup -PathType Leaf)) {
    Copy-Item -LiteralPath $avdConfig -Destination $avdConfigBackup
}
Set-IniValue -Path $avdConfig -Key 'image.sysdir.1' -Value "$customRelativePath\"

Write-Host 'Magisk ramdisk patch verified and the AVD now points to the isolated image.' -ForegroundColor Green
Write-Host "Original: $beforeHash"
Write-Host "Patched:  $patchedHash"
