[CmdletBinding()]
param(
    [string]$SdkPath,
    [switch]$NonInteractive,
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $repositoryRoot 'scripts\Common.ps1')
$config = Get-ToolkitConfig -RepositoryRoot $repositoryRoot
$sdkRoot = Get-AndroidSdkPath -SdkPath $SdkPath
$adb = Get-SdkToolPath -SdkPath $sdkRoot -ToolName 'adb.exe' -RelativeCandidates @('platform-tools\adb.exe')
$serial = Get-AvdSerial -AdbPath $adb -AvdName $config.AvdName
if (-not $serial) { throw "AVD '$($config.AvdName)' is not running." }

$androidJar = Join-Path $sdkRoot "platforms\android-$($config.ApiLevel)\android.jar"
$buildTools = Join-Path $sdkRoot "build-tools\$($config.BuildToolsVersion)"
$aapt = Join-Path $buildTools 'aapt.exe'
$d8 = Join-Path $buildTools 'd8.bat'
$zipalign = Join-Path $buildTools 'zipalign.exe'
$apkSigner = Join-Path $buildTools 'apksigner.bat'
foreach ($requiredTool in @($androidJar, $aapt, $d8, $zipalign, $apkSigner)) {
    if (-not (Test-Path -LiteralPath $requiredTool -PathType Leaf)) { throw "Required build tool not found: $requiredTool" }
}

$javacCommand = Get-Command javac.exe -ErrorAction SilentlyContinue
$javac = if ($javacCommand) { $javacCommand.Source } else { $null }
if (-not $javac -and $env:JAVA_HOME) {
    $candidate = Join-Path $env:JAVA_HOME 'bin\javac.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $javac = $candidate }
}
if (-not $javac) {
    $candidate = 'C:\Program Files\Android\Android Studio\jbr\bin\javac.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $javac = $candidate }
}
if (-not $javac) { throw 'javac.exe was not found. Install JDK 17 or Android Studio.' }
$jdkBin = Split-Path -Parent $javac
$jar = Join-Path $jdkBin 'jar.exe'
$keytool = Join-Path $jdkBin 'keytool.exe'
if (-not (Test-Path -LiteralPath $jar -PathType Leaf)) { throw "jar.exe not found beside javac.exe: $jdkBin" }
if (-not (Test-Path -LiteralPath $keytool -PathType Leaf)) { throw "keytool.exe not found beside javac.exe: $jdkBin" }

$cacheRoot = Resolve-ContainedPath -BasePath $repositoryRoot -ChildPath '.cache\root-probe'
if (Test-Path -LiteralPath $cacheRoot) { Remove-Item -LiteralPath $cacheRoot -Recurse -Force }
$classesDirectory = Join-Path $cacheRoot 'classes'
$dexDirectory = Join-Path $cacheRoot 'dex'
New-Item -ItemType Directory -Path $classesDirectory, $dexDirectory -Force | Out-Null

$classesJar = Join-Path $cacheRoot 'root-probe-classes.jar'
$unsignedApk = Join-Path $cacheRoot 'root-probe-unsigned.apk'
$alignedApk = Join-Path $cacheRoot 'root-probe-aligned.apk'
$signedApk = Join-Path $cacheRoot 'root-probe.apk'
$keystore = Join-Path $cacheRoot 'debug.keystore'
$manifest = Join-Path $PSScriptRoot 'AndroidManifest.xml'
$source = Join-Path $PSScriptRoot 'RootProbeActivity.java'
$deviceResult = '/sdcard/root-probe-result.xml'
$installed = $false

try {
    Write-Step -Message 'Compiling the app-level root probe'
    Invoke-CheckedProcess -FilePath $javac -ArgumentList @(
        '-encoding', 'UTF-8',
        '--release', '17',
        '-classpath', $androidJar,
        '-d', $classesDirectory,
        $source
    ) | Out-Null
    Invoke-CheckedProcess -FilePath $jar -ArgumentList @('cf', $classesJar, '-C', $classesDirectory, '.') | Out-Null
    Invoke-CheckedProcess -FilePath $d8 -ArgumentList @('--lib', $androidJar, '--min-api', '29', '--output', $dexDirectory, $classesJar) | Out-Null
    Invoke-CheckedProcess -FilePath $aapt -ArgumentList @('package', '-f', '-M', $manifest, '-I', $androidJar, '-F', $unsignedApk) | Out-Null
    Invoke-CheckedProcess -FilePath $aapt -ArgumentList @('add', $unsignedApk, 'classes.dex') -WorkingDirectory $dexDirectory | Out-Null
    Invoke-CheckedProcess -FilePath $zipalign -ArgumentList @('-f', '4', $unsignedApk, $alignedApk) | Out-Null
    Invoke-CheckedProcess -FilePath $keytool -ArgumentList @(
        '-genkeypair', '-noprompt',
        '-keystore', $keystore,
        '-storepass', 'android',
        '-alias', 'androiddebugkey',
        '-keypass', 'android',
        '-dname', 'CN=Android Debug,O=Android,C=US',
        '-keyalg', 'RSA',
        '-keysize', '2048',
        '-validity', '10000'
    ) | Out-Null
    Invoke-CheckedProcess -FilePath $apkSigner -ArgumentList @(
        'sign',
        '--ks', $keystore,
        '--ks-pass', 'pass:android',
        '--key-pass', 'pass:android',
        '--ks-key-alias', 'androiddebugkey',
        '--out', $signedApk,
        $alignedApk
    ) | Out-Null
    Invoke-CheckedProcess -FilePath $apkSigner -ArgumentList @('verify', '--verbose', $signedApk) | Out-Null

    & $adb -s $serial uninstall $config.RootProbePackage *> $null
    & $adb -s $serial install -r -d $signedApk
    if ($LASTEXITCODE -ne 0) { throw 'Root probe APK installation failed.' }
    $installed = $true
    & $adb -s $serial shell am start -W -n "$($config.RootProbePackage)/.RootProbeActivity" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Root probe activity could not be launched.' }

    if (-not $NonInteractive) {
        Write-Host 'Grant the Root Probe request in Magisk. If no dialog appears, open Magisk > Superuser and enable Root Probe.' -ForegroundColor Yellow
        Read-Host 'After the app displays its result, press Enter'
    } else {
        Start-Sleep -Seconds 3
    }

    & $adb -s $serial shell uiautomator dump $deviceResult | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the root probe UI.' }
    $uiXml = (& $adb -s $serial exec-out cat $deviceResult) -join "`n"
    if (-not $uiXml.Contains('exit=0') -or -not $uiXml.Contains('uid=0(root)')) {
        throw "App-level root verification failed.`n$uiXml"
    }

    $packageDump = (& $adb -s $serial shell dumpsys package $config.RootProbePackage) -join "`n"
    $uidMatch = [regex]::Match($packageDump, '(?:userId|appId)=(\d+)')
    if (-not $uidMatch.Success -or [int]$uidMatch.Groups[1].Value -lt 10000) {
        throw 'The root probe did not run under a normal application UID.'
    }

    Write-Host "App-level root verification passed for UID $($uidMatch.Groups[1].Value)." -ForegroundColor Green
    Write-Host 'Result: exit=0, uid=0(root)'
} finally {
    if ($installed) { & $adb -s $serial uninstall $config.RootProbePackage *> $null }
    & $adb -s $serial shell rm -f $deviceResult *> $null
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $cacheRoot)) {
        Remove-Item -LiteralPath $cacheRoot -Recurse -Force
    }
}
