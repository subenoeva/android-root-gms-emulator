[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Failures = New-Object System.Collections.Generic.List[string]
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Add-Failure {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:Failures.Add($Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) { Add-Failure -Message $Message }
}

function Assert-Equal {
    param(
        [AllowNull()]$Actual,
        [AllowNull()]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Actual -ne $Expected) {
        Add-Failure -Message "$Message. Expected '$Expected', got '$Actual'."
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Message
    )
    try {
        & $Action
        Add-Failure -Message $Message
    } catch {
        Write-Host "PASS: expected exception: $($_.Exception.Message)" -ForegroundColor DarkGreen
    }
}

function Assert-FileContains {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$LiteralText
    )
    $path = Join-Path $repositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure -Message "Missing $RelativePath"
        return
    }
    $content = Get-Content -LiteralPath $path -Raw
    if (-not $content.Contains($LiteralText)) {
        Add-Failure -Message "$RelativePath does not contain '$LiteralText'"
    }
}

Write-Host 'Repository contract' -ForegroundColor Cyan
$requiredFiles = @('config.psd1', '.gitignore', 'LICENSE')
foreach ($relativePath in $requiredFiles) {
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $repositoryRoot $relativePath) -PathType Leaf) -Message "Missing $relativePath"
}

$configPath = Join-Path $repositoryRoot 'config.psd1'
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $config = Import-PowerShellDataFile -LiteralPath $configPath
    Assert-Equal -Actual $config.AvdName -Expected 'Root_GMS_API_36' -Message 'Unexpected AVD name'
    Assert-Equal -Actual $config.ApiLevel -Expected 36 -Message 'Unexpected API level'
    Assert-Equal -Actual $config.Abi -Expected 'x86_64' -Message 'Unexpected ABI'
    Assert-Equal -Actual $config.SourceTag -Expected 'google_apis' -Message 'Unexpected source tag'
    Assert-Equal -Actual $config.CustomTag -Expected 'google_apis_magisk' -Message 'Unexpected custom tag'
    Assert-Equal -Actual $config.MagiskVersion -Expected '30.7' -Message 'Unexpected Magisk version'
    Assert-Equal -Actual $config.MagiskSha256 -Expected 'E0D32D2123532860F97123D927B1BB86C4E08E6FD8A48BFC6B5BEE0AFAE9EBD5' -Message 'Unexpected Magisk hash'
    Assert-Equal -Actual $config.RootAvdCommit -Expected '92df40eafa2f117053f56015e3c32ca706a55fa9' -Message 'Unexpected rootAVD commit'
}

if ($script:Failures.Count -gt 0) {
    Write-Host "$($script:Failures.Count) test(s) failed." -ForegroundColor Red
    exit 1
}

Write-Host 'All toolkit tests passed.' -ForegroundColor Green
exit 0
