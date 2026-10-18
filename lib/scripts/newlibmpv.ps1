$ErrorActionPreference = "Stop"

$Workspace = if ([string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) {
    (Get-Location).Path
} else {
    $env:GITHUB_WORKSPACE
}
$NewLibmpvPatch = Join-Path $Workspace "lib/scripts/newlibmpv.patch"
$SubtitlePatch = Join-Path $Workspace "lib/scripts/media_kit_secondary_subtitle.patch"
$ExpectedMediaKitSha = "1ea01b6fc5f4a4762bd99a018e858a7d155d6fca"
$MediaKitPackages = @(
    "media_kit",
    "media_kit_libs_android_video",
    "media_kit_libs_ios_video",
    "media_kit_libs_video",
    "media_kit_libs_windows_video",
    "media_kit_native_event_loop",
    "media_kit_video"
)

function Invoke-GitPatch {
    param(
        [Parameter(Mandatory = $true)][string]$PatchPath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    & git apply --ignore-space-change --check -- $PatchPath *> $null
    $forwardCheckExit = $LASTEXITCODE
    if ($forwardCheckExit -eq 0) {
        & git apply --ignore-space-change -- $PatchPath
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$Description applied"
            return
        }
        throw "failed to apply $Description (exit $LASTEXITCODE)"
    }

    & git apply --ignore-space-change --reverse --check -- $PatchPath *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$Description already applied"
        return
    }
    throw "failed to apply ${Description}: patch matches neither the original nor the already-applied state"
}

function Get-GitOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = & git -C $Path @Arguments 2>$null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed in $Path (exit $exitCode)"
    }
    return ($output | Out-String).Trim()
}

Set-Location $Workspace
Invoke-GitPatch -PatchPath $NewLibmpvPatch -Description "NewLibmpv dependency/source patch"

& flutter pub get
if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get failed (exit $LASTEXITCODE)"
}

$LockPath = Join-Path $Workspace "pubspec.lock"
if (-not (Test-Path $LockPath)) {
    throw "pubspec.lock is missing after flutter pub get"
}
$LockText = Get-Content $LockPath -Raw
$LockEntries = [regex]::Matches(
    $LockText,
    '(?ms)^  ([^\s:\r\n][^:\r\n]*):\r?\n(.*?)(?=^  [^\s:\r\n][^:\r\n]*:\r?$|\z)'
)
foreach ($packageName in $MediaKitPackages) {
    $entry = $LockEntries |
        Where-Object { $_.Groups[1].Value -eq $packageName } |
        Select-Object -First 1
    if ($null -eq $entry) {
        throw "$packageName is missing from pubspec.lock"
    }
    $body = $entry.Groups[2].Value
    $ref = [regex]::Match($body, '(?m)^\s+ref:\s*"?([0-9a-f]{40})"?\s*$')
    $resolvedRef = [regex]::Match($body, '(?m)^\s+resolved-ref:\s*"?([0-9a-f]{40})"?\s*$')
    if (-not $ref.Success -or $ref.Groups[1].Value -ne $ExpectedMediaKitSha) {
        throw "$packageName lock ref does not match $ExpectedMediaKitSha"
    }
    if (-not $resolvedRef.Success -or $resolvedRef.Groups[1].Value -ne $ExpectedMediaKitSha) {
        throw "$packageName resolved-ref does not match $ExpectedMediaKitSha"
    }
}
Write-Host "pubspec.lock pins all media-kit packages to $ExpectedMediaKitSha"

$PackageConfigPath = Join-Path $Workspace ".dart_tool/package_config.json"
if (-not (Test-Path $PackageConfigPath)) {
    throw "package config is missing after flutter pub get"
}
$PackageConfig = Get-Content $PackageConfigPath -Raw | ConvertFrom-Json
$MediaKitRepoRoot = $null
foreach ($packageName in $MediaKitPackages) {
    $package = $PackageConfig.packages |
        Where-Object { $_.name -eq $packageName } |
        Select-Object -First 1
    if ($null -eq $package) {
        throw "$packageName is missing from package_config.json"
    }
    $packageRoot = ([System.Uri]$package.rootUri).LocalPath
    if (-not (Test-Path $packageRoot)) {
        throw "$packageName package directory does not exist: $packageRoot"
    }
    $repoRoot = Get-GitOutput -Path $packageRoot -Arguments @("rev-parse", "--show-toplevel")
    $checkoutSha = Get-GitOutput -Path $packageRoot -Arguments @("rev-parse", "HEAD")
    if ($checkoutSha -ne $ExpectedMediaKitSha) {
        throw "$packageName checkout is $checkoutSha, expected $ExpectedMediaKitSha"
    }
    if ($null -eq $MediaKitRepoRoot) {
        $MediaKitRepoRoot = $repoRoot
    } elseif (-not [string]::Equals($MediaKitRepoRoot, $repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "media-kit packages resolve from different Git checkouts"
    }
}
Write-Host "all media-kit package checkouts resolve to $ExpectedMediaKitSha"

Set-Location $MediaKitRepoRoot
Invoke-GitPatch -PatchPath $SubtitlePatch -Description "PiliMax secondary-subtitle compatibility patch"
& git diff --check
if ($LASTEXITCODE -ne 0) {
    throw "git diff --check failed in the media-kit checkout (exit $LASTEXITCODE)"
}
