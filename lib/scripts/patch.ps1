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

    Write-Error "failed to apply ${Description}: patch matches neither the original nor the already-applied state"
    return $false
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
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter pub get failed (exit $LASTEXITCODE)"
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

Set-Location $Workspace
