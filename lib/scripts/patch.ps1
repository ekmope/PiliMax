param(
    [string]$platform = ""
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

$LayoutBuilderPatch = "lib/scripts/layout_builder.patch"

# Upstream issue #2308
$NavigationDrawerPatch = "lib/scripts/navigation_drawer.patch"

$PopupMenuPatch = "lib/scripts/popup_menu.patch"

$FABPatch = "lib/scripts/fab.patch"

$SelectableRegionSelectionPatch = "lib/scripts/selectable_region.patch"

$ScrollPositionPatch = "lib/scripts/scroll_position.patch"

$ScrollablePatch = "lib/scripts/scrollable.patch"

$DraggableScrollableSheetPatch = "lib/scripts/draggable_scrollable_sheet.patch"

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

if ($platform.ToLower() -eq "ios") {
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
    git apply "$env:GITHUB_WORKSPACE/$patch"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$patch applied"
    } else {
        Write-Error "failed to apply $patch (exit $LASTEXITCODE)"
        exit 1
    }
}
