param(
    [string]$platform = ""
)

# TODO: remove
# https://github.com/flutter/flutter/issues/182281
$NewOverScrollIndicator = "362b1de29974ffc1ed6faa826e1df870d7bec75f";

$BottomSheetAndroidPatch = "lib/scripts/bottom_sheet_android.patch"

# Upstream issue #1906
$BottomSheetIOSFlutterPatch = "lib/scripts/bottom_sheet_ios_flutter.patch"
$BottomSheetIOSPiliMaxPatch = "lib/scripts/bottom_sheet_ios_pilimax.patch"

# Upstream issue #1662
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
    }
    git apply $GeetestIOSPatch
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$GeetestIOSPatch applied"
    }
}

Set-Location $env:FLUTTER_ROOT

$picks   = @()
$reverts = @()
$patches = @($ModalBarrierPatch, $TextSelectionPatch, $MouseCursorPatch,
            $ImageAnimPatch, $LayoutBuilderPatch, $NavigationDrawerPatch,
            $PopupMenuPatch, $FABPatch, $SelectableRegionPatch, $SelectableRegionSelectionPatch)

switch ($platform.ToLower()) {
    "android" {
        $reverts += $NewOverScrollIndicator
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

git config --global user.name "ci"
git config --global user.email "example@example.com"

git reset --hard HEAD

foreach ($pick in $picks) {
    git stash
    git cherry-pick $pick --no-edit
    if ($LASTEXITCODE -eq 0) {
        git reset --soft HEAD~1
        Write-Host "$pick picked"
    }
    git stash pop
}

foreach ($revert in $reverts) {
    git stash
    git revert $revert --no-edit
    if ($LASTEXITCODE -eq 0) {
        git reset --soft HEAD~1
        Write-Host "$revert reverted"
    }
    git stash pop
}

foreach ($patch in $patches) {
    git apply "$env:GITHUB_WORKSPACE/$patch"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$patch applied"
    }
}

# TODO: remove
if ($platform.ToLower() -eq "android") {
    "df67bb3b55323961184ae7117cc91c054f36a42c" | Set-Content -Path .\bin\internal\engine.version
    Remove-Item -Path ".\bin\cache" -Recurse -Force
    flutter --version
}
