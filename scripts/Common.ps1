Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ToolkitConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $configPath = Join-Path ([System.IO.Path]::GetFullPath($RepositoryRoot)) 'config.psd1'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Toolkit configuration not found: $configPath"
    }
    Import-PowerShellDataFile -LiteralPath $configPath
}

function Get-AndroidSdkPath {
    [CmdletBinding()]
    param([string]$SdkPath)

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($SdkPath) { $candidates.Add($SdkPath) }
    if ($env:ANDROID_SDK_ROOT) { $candidates.Add($env:ANDROID_SDK_ROOT) }
    if ($env:ANDROID_HOME) { $candidates.Add($env:ANDROID_HOME) }
    if ($env:LOCALAPPDATA) { $candidates.Add((Join-Path $env:LOCALAPPDATA 'Android\Sdk')) }

    foreach ($candidate in $candidates) {
        $fullPath = [System.IO.Path]::GetFullPath($candidate)
        if (Test-Path -LiteralPath $fullPath -PathType Container) { return $fullPath }
    }
    throw 'Android SDK not found. Set ANDROID_SDK_ROOT or install Android Studio with the SDK.'
}

function Get-AvdHome {
    [CmdletBinding()]
    param()

    if ($env:ANDROID_AVD_HOME) { return [System.IO.Path]::GetFullPath($env:ANDROID_AVD_HOME) }
    if (-not $env:USERPROFILE) { throw 'USERPROFILE is not defined.' }
    [System.IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.android\avd'))
}

function Resolve-ContainedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ChildPath
    )

    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\')
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $base $ChildPath))
    if (-not $candidate.StartsWith($base + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes base directory: $candidate"
    }
    $candidate
}

function Get-Sha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "File not found: $Path" }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-SdkToolPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SdkPath,
        [Parameter(Mandatory = $true)][string[]]$RelativeCandidates,
        [Parameter(Mandatory = $true)][string]$ToolName
    )

    foreach ($relativePath in $RelativeCandidates) {
        $candidate = Join-Path $SdkPath $relativePath
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw "$ToolName not found below Android SDK: $SdkPath"
}

function Invoke-CheckedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory,
        [int[]]$AllowedExitCodes = @(0)
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "Executable not found: $FilePath" }
    $previousLocation = Get-Location
    try {
        if ($WorkingDirectory) { Set-Location -LiteralPath $WorkingDirectory }
        & $FilePath @ArgumentList
        $exitCode = $LASTEXITCODE
    } finally {
        Set-Location -LiteralPath $previousLocation
    }
    if ($AllowedExitCodes -notcontains $exitCode) {
        throw "Process failed with exit code ${exitCode}: $FilePath $($ArgumentList -join ' ')"
    }
    $exitCode
}

function Get-AvdSerial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AdbPath,
        [Parameter(Mandatory = $true)][string]$AvdName
    )

    $matches = New-Object System.Collections.Generic.List[string]
    $deviceLines = & $AdbPath devices
    foreach ($line in $deviceLines) {
        if ($line -notmatch '^(emulator-\d+)\s+device$') { continue }
        $serial = $Matches[1]
        $reportedName = (& $AdbPath -s $serial emu avd name 2>$null) |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -ne 'OK' } |
            Select-Object -First 1
        if ($reportedName -eq $AvdName) { $matches.Add($serial) }
    }
    if ($matches.Count -gt 1) { throw "More than one running emulator reports AVD name '$AvdName'." }
    if ($matches.Count -eq 1) { return $matches[0] }
    $null
}

function Wait-ForAvdSerial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AdbPath,
        [Parameter(Mandatory = $true)][string]$AvdName,
        [int]$TimeoutSeconds = 300
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $serial = Get-AvdSerial -AdbPath $AdbPath -AvdName $AvdName
        if ($serial) { return $serial }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for AVD '$AvdName'."
}

function Wait-ForAndroidBoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AdbPath,
        [Parameter(Mandatory = $true)][string]$Serial,
        [int]$TimeoutSeconds = 300
    )

    & $AdbPath -s $Serial wait-for-device | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ADB could not reach $Serial." }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $completed = (& $AdbPath -s $Serial shell getprop sys.boot_completed 2>$null).Trim()
        if ($completed -eq '1') { return }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for Android boot on $Serial."
}

function Set-IniValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "INI file not found: $Path" }
    $lines = Get-Content -LiteralPath $Path
    $prefix = "$Key="
    $found = $false
    $updated = foreach ($line in $lines) {
        if ($line.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $found = $true
            "$prefix$Value"
        } else {
            $line
        }
    }
    if (-not $found) { $updated += "$prefix$Value" }
    [System.IO.File]::WriteAllLines($Path, [string[]]$updated, (New-Object System.Text.UTF8Encoding($false)))
}

function Assert-FreeSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$MinimumGigabytes
    )

    $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($Path))
    $drive = New-Object System.IO.DriveInfo($root)
    $freeGigabytes = [math]::Floor($drive.AvailableFreeSpace / 1GB)
    if ($freeGigabytes -lt $MinimumGigabytes) {
        throw "At least $MinimumGigabytes GB free are required on $root; $freeGigabytes GB are available."
    }
    $freeGigabytes
}

function Write-Step {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}
