param(
    [string]$platform = ""
)

$Workspace = if ([string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) {
    (Get-Location).Path
} else {
    $env:GITHUB_WORKSPACE
}

$MaterialPatches = @(
    "lib/scripts/material/modal_barrier_material.patch",
    "lib/scripts/material/navigation_drawer.patch",
    "lib/scripts/material/popup_menu.patch",
    "lib/scripts/material/refresh_indicator.patch",
    "lib/scripts/material/text_field.patch"
)

$BottomSheetAndroidPatch = "lib/scripts/bottom_sheet_android.patch"

# Upstream issue #1906
$BottomSheetIOSFlutterPatch = "lib/scripts/bottom_sheet_ios_flutter.patch"
$BottomSheetIOSPiliMaxPatch = "lib/scripts/bottom_sheet_ios_pilimax.patch"

# https://github.com/bggRGjQaUbCoE/PiliPlus/issues/1662
# handle bottom scroll event
$ScrollViewPatch = "lib/scripts/scroll_view.patch"

# Upstream issue #2106
$TextSelectionPatch = "lib/scripts/text_selection.patch"

# Upstream issue #1947
$NavigatorPatch = "lib/scripts/navigator.patch"

# Upstream issue #2107
$ImageAnimPatch = "lib/scripts/image_anim.patch"

# fix predictive back direction after popping a nested route
# (route below mounts the transition with a null back event during another
#  route's gesture; direction tween is never recomputed on later gestures)
$PredictiveBackPatch = "lib/scripts/predictive_back_page_transitions_builder.patch"

$LayoutBuilderPatch = "lib/scripts/layout_builder.patch"

# Upstream issue #2308
$NavigationDrawerPatch = "lib/scripts/navigation_drawer.patch"

$PopupMenuPatch = "lib/scripts/popup_menu.patch"

$FABPatch = "lib/scripts/fab.patch"

$SelectableRegionSelectionPatch = "lib/scripts/selectable_region.patch"

$ScrollPositionPatch = "lib/scripts/scroll_position.patch"

$ScrollablePatch = "lib/scripts/scrollable.patch"

$DraggableScrollableSheetPatch = "lib/scripts/draggable_scrollable_sheet.patch"

# Keep PiP-retained GetX controllers reusable after their route is removed.
$GetxLifecyclePatch = "lib/scripts/getx_lifecycle.patch"

# Restore Android predictive-back for standard GetPageRoute transitions.
$GetxPredictiveBackPatch = "lib/scripts/getx_predictive_back.patch"

# Keep PiliMax's bilingual subtitle API compatible with the native media-kit
# fork used by CI. The fork's native branch contains the platform fixes but
# does not include the secondary subtitle API used by the app.
$MediaKitSecondarySubtitlePatch = "lib/scripts/media_kit_secondary_subtitle.patch"

$RefreshIndicatorPatch = "lib/scripts/refresh_indicator.patch"

# TODO: remove
# https://github.com/flutter/flutter/pull/183261
$SelectableRegionPatch = "lib/scripts/null_safety_for_selectable_region.patch"

# TODO: remove
# https://github.com/flutter/flutter/issues/90223
$ModalBarrierPatch = "lib/scripts/modal_barrier.patch"

# TODO: remove
# https://github.com/flutter/flutter/issues/182466
$MouseCursorPatch = "lib/scripts/mouse_cursor.patch"

$GeetestIOSPatch = "lib/scripts/geetest_ios.patch"

# Pub cache entries can survive between CI runs. Apply a dependency patch only
# when it is missing, and accept an exact reverse match as already applied.
function Apply-DependencyPatch {
    param(
        [Parameter(Mandatory = $true)][string]$PatchPath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    & git apply --ignore-space-change --check -- $PatchPath *> $null
    $forwardCheckExit = $LASTEXITCODE
    if ($forwardCheckExit -eq 0) {
        & git apply --ignore-space-change -- $PatchPath
        $applyExit = $LASTEXITCODE
        if ($applyExit -eq 0) {
            Write-Host "$Description applied"
            return $true
        }
        Write-Error "failed to apply $Description (exit $applyExit)"
        return $false
    }

    & git apply --ignore-space-change --reverse --check -- $PatchPath *> $null
    $reverseCheckExit = $LASTEXITCODE
    if ($reverseCheckExit -eq 0) {
        Write-Host "$Description already applied"
        return $true
    }

    if ($Description -eq "$MediaKitSecondarySubtitlePatch to media-kit packages" -and
        (Test-MediaKitSecondarySubtitlePatchApplied -RepositoryRoot $MediaKitRepoRoot)) {
        Write-Host "$Description already applied (compatible cached implementation)"
        $global:LASTEXITCODE = 0
        return $true
    }

    Write-Error "failed to apply ${Description}: patch matches neither the original nor the already-applied state"
    return $false
}

function Test-MediaKitSecondarySubtitlePatchApplied {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $requiredMarkers = @(
        @{
            Path = "media_kit/lib/src/models/track.dart"
            Text = "final SubtitleTrack secondarySubtitle;"
        },
        @{
            Path = "media_kit/lib/src/player/native/player/real.dart"
            Text = "Future<void> setSecondarySubtitleTrack("
        },
        @{
            Path = "media_kit/lib/src/player/platform_player.dart"
            Text = "[PlatformPlayer.setSecondarySubtitleTrack] is not implemented"
        },
        @{
            Path = "media_kit_video/lib/src/subtitle/subtitle_view.dart"
            Text = "configuration.secondaryStyle"
        }
    )

    foreach ($marker in $requiredMarkers) {
        $path = Join-Path $RepositoryRoot $marker.Path
        if (-not (Test-Path $path)) {
            return $false
        }
        if (-not (Get-Content $path -Raw).Contains($marker.Text)) {
            return $false
        }
    }

    return $true
}

function Apply-MediaKitAndroidDownloadRetry {
    param([Parameter(Mandatory = $true)][string]$PackageRoot)

    $gradlePath = Join-Path $PackageRoot "android/build.gradle"
    if (-not (Test-Path $gradlePath)) {
        throw "media_kit Android build.gradle does not exist: $gradlePath"
    }

    $content = [System.IO.File]::ReadAllText($gradlePath)
    if ($content.Contains("def downloadWithRetry = { String url, File destination ->")) {
        if (-not $content.Contains("downloadWithRetry(fileInfo.url, destFile)")) {
            throw "media_kit Android build.gradle contains a partial download retry patch"
        }
        return
    }

    $lineEnding = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $loopAnchor = "        filesToDownload.each { fileInfo ->"
    if (-not $content.Contains($loopAnchor)) {
        throw "media_kit Android build.gradle has an unexpected dependency loop"
    }
    $downloadBlock =
        "                destFile.withOutputStream { os ->" + $lineEnding +
        "                    os << new URL(fileInfo.url).openStream()" + $lineEnding +
        "                }"
    if (-not $content.Contains($downloadBlock)) {
        throw "media_kit Android build.gradle has an unexpected download command"
    }

    $helper = @'
        def downloadWithRetry = { String url, File destination ->
            int maxAttempts = 6
            Exception lastException = null
            for (int attempt = 1; attempt <= maxAttempts; attempt++) {
                File partFile = new File(destination.parentFile, "${destination.name}.part")
                try {
                    partFile.delete()
                    def connection = new URL(url).openConnection()
                    connection.setConnectTimeout(20000)
                    connection.setReadTimeout(120000)
                    connection.setUseCaches(false)
                    if (connection instanceof java.net.HttpURLConnection) {
                        int status = connection.responseCode
                        if (status >= 400 && status < 500 && status != 429) {
                            throw new GradleException("HTTP ${status} while downloading ${url}")
                        }
                        if (status == 429 || status >= 500) {
                            throw new java.io.IOException("HTTP ${status} while downloading ${url}")
                        }
                    }
                    def input = connection.inputStream
                    try {
                        partFile.withOutputStream { output -> output << input }
                    } finally {
                        input.close()
                    }
                    if (!partFile.renameTo(destination)) {
                        throw new java.io.IOException("Unable to move ${partFile} to ${destination}")
                    }
                    return
                } catch (GradleException exception) {
                    partFile.delete()
                    throw exception
                } catch (java.io.IOException exception) {
                    lastException = exception
                    partFile.delete()
                    if (attempt < maxAttempts) {
                        println "Transient download failure for ${url} (attempt ${attempt}/${maxAttempts}); retrying"
                        sleep(attempt * 10000L)
                    }
                }
            }
            throw new GradleException("Failed to download ${url} after ${maxAttempts} attempts", lastException)
        }
'@
    $helper = $helper -replace "`r?`n", $lineEnding
    $updated = $content.Replace($loopAnchor, $helper + $lineEnding + $loopAnchor)
    $updated = $updated.Replace(
        $downloadBlock,
        "                downloadWithRetry(fileInfo.url, destFile)"
    )
    if (-not $updated.Contains("downloadWithRetry(fileInfo.url, destFile)")) {
        throw "failed to replace media_kit Android download command"
    }
    [System.IO.File]::WriteAllText(
        $gradlePath,
        $updated,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Invoke-FlutterPubGetWithRetry {
    param([int]$MaxAttempts = 3)

    $retryPattern = '(?i)(502|503|504|bad gateway|service unavailable|gateway timeout|timed out|connection reset|could not resolve host|failed host lookup|unexpected end of file)'
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $pubGetOutput = @(& flutter pub get 2>&1)
        $pubGetExitCode = $LASTEXITCODE
        $pubGetOutput | ForEach-Object { Write-Host $_ }
        if ($pubGetExitCode -eq 0) {
            return 0
        }

        $pubGetText = $pubGetOutput -join "`n"
        if ($attempt -lt $MaxAttempts -and $pubGetText -match $retryPattern) {
            Write-Warning "flutter pub get failed with a transient network error; retrying ($attempt/$MaxAttempts)."
            Start-Sleep -Seconds ($attempt * 10)
            continue
        }
        return $pubGetExitCode
    }
    return 1
}

function Apply-MediaKitMacOSDownloadRetry {
    param([Parameter(Mandatory = $true)][string]$PackageRoot)

    $makefilePath = Join-Path $PackageRoot "macos/Makefile"
    if (-not (Test-Path $makefilePath)) {
        throw "media_kit macOS Makefile does not exist: $makefilePath"
    }
    $content = [System.IO.File]::ReadAllText($makefilePath)
    $lineEnding = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $retryOptions = 'curl --fail --location --retry 8 --retry-all-errors --retry-delay 10 \' +
        $lineEnding + "`t`t" +
        '--retry-max-time 600 --connect-timeout 30 --max-time 300 \' +
        $lineEnding
    if ($content.Contains($retryOptions)) {
        return
    }
    $old = 'curl -L \' + $lineEnding
    $oldRetryOptions = 'curl --fail --location --retry 4 --retry-all-errors --retry-delay 2 \' +
        $lineEnding + "`t`t" +
        '--retry-max-time 180 --connect-timeout 20 --max-time 120 \' +
        $lineEnding
    if ($content.Contains($old)) {
        $updated = $content.Replace($old, $retryOptions)
    } elseif ($content.Contains($oldRetryOptions)) {
        $updated = $content.Replace($oldRetryOptions, $retryOptions)
    } else {
        throw "media_kit macOS Makefile has an unexpected curl command"
    }
    [System.IO.File]::WriteAllText(
        $makefilePath,
        $updated,
        [System.Text.UTF8Encoding]::new($false)
    )
}

if ($platform.ToLower() -eq "ios") {
    Set-Location $Workspace
    git apply $BottomSheetIOSPiliMaxPatch
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$BottomSheetIOSPiliMaxPatch applied"
    } else {
        Write-Error "failed to apply $BottomSheetIOSPiliMaxPatch (exit $LASTEXITCODE)"
        exit 1
    }
    git apply $GeetestIOSPatch
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$GeetestIOSPatch applied"
    } else {
        Write-Error "failed to apply $GeetestIOSPatch (exit $LASTEXITCODE)"
        exit 1
    }
}

Set-Location $Workspace
$pubGetStatus = Invoke-FlutterPubGetWithRetry
if ($pubGetStatus -ne 0) {
    Write-Error "flutter pub get failed (exit $pubGetStatus)"
    exit 1
}

$PackageConfigPath = Join-Path $Workspace ".dart_tool/package_config.json"
if (-not (Test-Path $PackageConfigPath)) {
    Write-Error "package config not found after flutter pub get: $PackageConfigPath"
    exit 1
}

try {
    $PackageConfig = Get-Content $PackageConfigPath -Raw | ConvertFrom-Json
    $MaterialPackage = $PackageConfig.packages |
        Where-Object { $_.name -eq "material_ui" } |
        Select-Object -First 1
    $GetPackage = $PackageConfig.packages |
        Where-Object { $_.name -eq "get" } |
        Select-Object -First 1
    $MediaKitPackage = $PackageConfig.packages |
        Where-Object { $_.name -eq "media_kit" } |
        Select-Object -First 1
    $MediaKitVideoPackage = $PackageConfig.packages |
        Where-Object { $_.name -eq "media_kit_video" } |
        Select-Object -First 1
    $MediaKitAndroidVideoPackage = $PackageConfig.packages |
        Where-Object { $_.name -eq "media_kit_libs_android_video" } |
        Select-Object -First 1
    $MediaKitMacosVideoPackage = $PackageConfig.packages |
        Where-Object { $_.name -eq "media_kit_libs_macos_video" } |
        Select-Object -First 1
    if ($null -eq $MaterialPackage) {
        throw "material_ui is missing from package_config.json"
    }
    $MaterialRoot = ([System.Uri]$MaterialPackage.rootUri).LocalPath
    if (-not (Test-Path $MaterialRoot)) {
        throw "material_ui directory does not exist: $MaterialRoot"
    }
    if ($null -eq $GetPackage) {
        throw "get is missing from package_config.json"
    }
    $GetRoot = ([System.Uri]$GetPackage.rootUri).LocalPath
    if (-not (Test-Path $GetRoot)) {
        throw "get directory does not exist: $GetRoot"
    }
    if ($null -eq $MediaKitPackage) {
        throw "media_kit is missing from package_config.json"
    }
    $MediaKitRoot = ([System.Uri]$MediaKitPackage.rootUri).LocalPath
    if (-not (Test-Path $MediaKitRoot)) {
        throw "media_kit directory does not exist: $MediaKitRoot"
    }
    if ($null -eq $MediaKitVideoPackage) {
        throw "media_kit_video is missing from package_config.json"
    }
    $MediaKitVideoRoot = ([System.Uri]$MediaKitVideoPackage.rootUri).LocalPath
    if (-not (Test-Path $MediaKitVideoRoot)) {
        throw "media_kit_video directory does not exist: $MediaKitVideoRoot"
    }
    $MediaKitRepoRoot = (& git -C $MediaKitRoot rev-parse --show-toplevel 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($MediaKitRepoRoot)) {
        throw "failed to locate media-kit git repository root"
    }
    $MediaKitVideoRepoRoot = (& git -C $MediaKitVideoRoot rev-parse --show-toplevel 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($MediaKitVideoRepoRoot)) {
        throw "failed to locate media-kit video git repository root"
    }
    if (-not [string]::Equals($MediaKitRepoRoot, $MediaKitVideoRepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "media_kit and media_kit_video are not from the same git repository"
    }

    $MediaKitMacosVideoRoot = $null
    $MediaKitAndroidVideoRoot = $null
    if ($platform.ToLower() -eq "android") {
        if ($null -eq $MediaKitAndroidVideoPackage) {
            throw "media_kit_libs_android_video is missing from package_config.json"
        }
        $MediaKitAndroidVideoRoot = ([System.Uri]$MediaKitAndroidVideoPackage.rootUri).LocalPath
        if (-not (Test-Path $MediaKitAndroidVideoRoot)) {
            throw "media_kit_libs_android_video directory does not exist: $MediaKitAndroidVideoRoot"
        }
    }
    if ($platform.ToLower() -eq "macos") {
        if ($null -eq $MediaKitMacosVideoPackage) {
            throw "media_kit_libs_macos_video is missing from package_config.json"
        }
        $MediaKitMacosVideoRoot = ([System.Uri]$MediaKitMacosVideoPackage.rootUri).LocalPath
        if (-not (Test-Path $MediaKitMacosVideoRoot)) {
            throw "media_kit_libs_macos_video directory does not exist: $MediaKitMacosVideoRoot"
        }
    }
} catch {
    Write-Error "failed to locate required dependency package: $($_.Exception.Message)"
    exit 1
}

Set-Location $env:FLUTTER_ROOT

$picks   = @()
$reverts = @()
$patches = @($ModalBarrierPatch, $TextSelectionPatch, $MouseCursorPatch,
            $ImageAnimPatch, $LayoutBuilderPatch, $NavigationDrawerPatch,
            $PopupMenuPatch, $FABPatch, $SelectableRegionPatch, $SelectableRegionSelectionPatch,
            $ScrollPositionPatch,
            $ScrollablePatch,
            $DraggableScrollableSheetPatch,
            $RefreshIndicatorPatch)

switch ($platform.ToLower()) {
    "android" {
        $patches += $BottomSheetAndroidPatch
        $patches += $ScrollViewPatch
        $patches += $NavigatorPatch
        $patches += $PredictiveBackPatch
    }
    "ios" {
        $patches += $ScrollViewPatch
        $patches += $BottomSheetIOSFlutterPatch
        $patches += $NavigatorPatch
    }
    "linux" {
    }
    "macos" {
    }
    "windows" {
    }
    default {}
}

git config user.name "ci"
git config user.email "example@example.com"

git reset --hard HEAD
if ($LASTEXITCODE -ne 0) {
    Write-Error "git reset --hard HEAD failed (exit $LASTEXITCODE)"
    exit 1
}

foreach ($pick in $picks) {
    git stash
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git stash failed before cherry-picking $pick (exit $LASTEXITCODE)"
        exit 1
    }
    try {
        git cherry-pick $pick --no-edit
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git cherry-pick $pick failed (exit $LASTEXITCODE)"
            exit 1
        }
        git reset --soft HEAD~1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git reset --soft HEAD~1 failed after $pick (exit $LASTEXITCODE)"
            exit 1
        }
        Write-Host "$pick picked"
    } finally {
        git stash pop
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git stash pop failed after $pick (exit $LASTEXITCODE)"
            exit 1
        }
    }
}

foreach ($revert in $reverts) {
    git stash
    if ($LASTEXITCODE -ne 0) {
        Write-Error "git stash failed before reverting $revert (exit $LASTEXITCODE)"
        exit 1
    }
    try {
        git revert $revert --no-edit
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git revert $revert failed (exit $LASTEXITCODE)"
            exit 1
        }
        git reset --soft HEAD~1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git reset --soft HEAD~1 failed after $revert (exit $LASTEXITCODE)"
            exit 1
        }
        Write-Host "$revert reverted"
    } finally {
        git stash pop
        if ($LASTEXITCODE -ne 0) {
            Write-Error "git stash pop failed after $revert (exit $LASTEXITCODE)"
            exit 1
        }
    }
}

foreach ($patch in $patches) {
    git apply (Join-Path $Workspace $patch)
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$patch applied"
    } else {
        Write-Error "failed to apply $patch (exit $LASTEXITCODE)"
        exit 1
    }
}

Set-Location $MaterialRoot
foreach ($patch in $MaterialPatches) {
    $patchPath = Join-Path $Workspace $patch
    if (-not (Apply-DependencyPatch -PatchPath $patchPath -Description "$patch to material_ui")) {
        exit 1
    }
}

Set-Location $GetRoot
if (-not (Apply-DependencyPatch -PatchPath (Join-Path $Workspace $GetxLifecyclePatch) -Description "$GetxLifecyclePatch to get")) {
    exit 1
}
if (-not (Apply-DependencyPatch -PatchPath (Join-Path $Workspace $GetxPredictiveBackPatch) -Description "$GetxPredictiveBackPatch to get")) {
    exit 1
}

Set-Location $MediaKitRepoRoot
if (-not (Apply-DependencyPatch -PatchPath (Join-Path $Workspace $MediaKitSecondarySubtitlePatch) -Description "$MediaKitSecondarySubtitlePatch to media-kit packages")) {
    exit 1
}

if ($platform.ToLower() -eq "macos") {
    try {
        Apply-MediaKitMacOSDownloadRetry -PackageRoot $MediaKitMacosVideoRoot
    } catch {
        Write-Error "failed to add media-kit macOS download retries: $($_.Exception.Message)"
        exit 1
    }
}

if ($platform.ToLower() -eq "android") {
    try {
        Apply-MediaKitAndroidDownloadRetry -PackageRoot $MediaKitAndroidVideoRoot
    } catch {
        Write-Error "failed to add media-kit Android download retries: $($_.Exception.Message)"
        exit 1
    }
}

Set-Location $Workspace
