param(
    [string]$AudioServicePackageRoot = "",
    [string]$JavaHome = ""
)

$ErrorActionPreference = "Stop"
$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$PendingIntentPatch = Join-Path $WorkspaceRoot "lib/scripts/audio_service_pending_intent.patch"
$ForegroundRecoveryPatch = Join-Path $WorkspaceRoot "lib/scripts/audio_service_foreground_recovery.patch"
$ServiceJavaDirectory = "audio_service/android/src/main/java/com/ryanheise/audioservice"
if ([string]::IsNullOrWhiteSpace($AudioServicePackageRoot)) {
    $config = Get-Content (Join-Path $WorkspaceRoot ".dart_tool/package_config.json") -Raw | ConvertFrom-Json
    $package = $config.packages | Where-Object name -eq "audio_service" | Select-Object -First 1
    if ($null -eq $package) { throw "audio_service is missing from package_config.json" }
    $AudioServicePackageRoot = ([Uri]$package.rootUri).LocalPath
}
$DependencyCheckout = & git -C $AudioServicePackageRoot rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { throw "audio_service must be resolved from its Git checkout" }
$java = if ($JavaHome) { Join-Path $JavaHome "bin/java.exe" } else { "java" }
$javac = if ($JavaHome) { Join-Path $JavaHome "bin/javac.exe" } else { "javac" }
$TemporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pilimax-pending-intent-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TemporaryRoot | Out-Null

function Get-JavaMethod {
    param([string]$Source, [string]$Signature)
    $start = $Source.IndexOf($Signature, [StringComparison]::Ordinal)
    if ($start -lt 0) { throw "Method missing from actual dependency: $Signature" }
    $brace = $Source.IndexOf('{', $start)
    $depth = 0
    for ($index = $brace; $index -lt $Source.Length; $index++) {
        if ($Source[$index] -eq '{') { $depth++ }
        if ($Source[$index] -eq '}') {
            $depth--
            if ($depth -eq 0) { return $Source.Substring($start, $index - $start + 1) }
        }
    }
    throw "Unterminated Java method: $Signature"
}

function Invoke-ActualJavaRegression {
    param([string]$Source, [string]$Name, [bool]$ExpectFailure = $false)
    $checkRoot = Join-Path $TemporaryRoot $Name
    New-Item -ItemType Directory -Path $checkRoot | Out-Null
    $methods = @(
        "NotificationCompat.Action createAction(",
        "PendingIntent buildCustomActionPendingIntent(",
        "PendingIntent buildMediaButtonPendingIntent(",
        "PendingIntent buildDeletePendingIntent(",
        "void setState("
    ) | ForEach-Object { Get-JavaMethod -Source $Source -Signature $_ }
    if ($Source.Contains("private int customKeyCode = 0;")) {
        $methods = @("private int customKeyCode = 0;") + $methods
    }
    $template = Get-Content (Join-Path $PSScriptRoot "AudioServicePendingIntentHarness.java") -Raw
    $generated = $template.Replace("/* ACTUAL_DEPENDENCY_METHODS */", ($methods -join "`n"))
    $generatedPath = Join-Path $checkRoot "AudioServicePendingIntentHarness.java"
    [IO.File]::WriteAllText($generatedPath, $generated, [Text.UTF8Encoding]::new($false))
    $sourceDirectory = Join-Path $TemporaryRoot $ServiceJavaDirectory
    & $javac -encoding UTF-8 -d $checkRoot $generatedPath (Join-Path $sourceDirectory "MediaControl.java") (Join-Path $sourceDirectory "CustomMediaAction.java")
    if ($LASTEXITCODE -ne 0) { throw "Java regression compile failed: $Name" }
    $output = @(& $java -cp $checkRoot com.ryanheise.audioservice.AudioServicePendingIntentHarness 2>&1)
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($ExpectFailure) {
        if ($exitCode -eq 0 -or ($output -join "`n") -notmatch 'position updates allocated') {
            throw "The unpatched dependency did not reproduce the PendingIntent regression"
        }
    } elseif ($exitCode -ne 0) {
        throw "Patched PendingIntent regression failed"
    }
}

Push-Location $TemporaryRoot
try {
    # Keep the same nested package layout as the Git checkout in the Pub cache.
    $archive = Join-Path $TemporaryRoot "audio_service.zip"
    & git -C $DependencyCheckout archive --format=zip --output=$archive HEAD -- $ServiceJavaDirectory
    if ($LASTEXITCODE -ne 0) { throw "Unable to export clean audio_service sources" }
    Expand-Archive -LiteralPath $archive -DestinationPath $TemporaryRoot
    & git init -q
    if ($LASTEXITCODE -ne 0) { throw "Unable to create isolated patch fixture" }
    $packageRoot = Join-Path $TemporaryRoot "audio_service"
    $javaDirectory = Join-Path $TemporaryRoot $ServiceJavaDirectory
    $serviceSource = Join-Path $javaDirectory "AudioService.java"
    $pluginSource = Join-Path $javaDirectory "AudioServicePlugin.java"
    Invoke-ActualJavaRegression -Source (Get-Content -LiteralPath $serviceSource -Raw) -Name "unpatched" -ExpectFailure $true

    # Load only the functions used by the Android patch step.
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $WorkspaceRoot "lib/scripts/patch.ps1"), [ref]$null, [ref]$parseErrors
    )
    if ($parseErrors.Count) { throw "patch.ps1 has parse errors" }
    foreach ($functionName in @("Apply-DependencyPatch", "Apply-AudioServicePatches")) {
        $helper = $ast.Find({ param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
        }, $true)
        if ($null -eq $helper) { throw "CI helper not found: $functionName" }
        . ([ScriptBlock]::Create($helper.Extent.Text))
    }
    $androidPatchCall = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq "Apply-AudioServicePatches"
    }, $true)
    if ($null -eq $androidPatchCall) { throw "patch.ps1 does not call the audio_service patch helper" }
    $runAndroidPatch = [ScriptBlock]::Create($androidPatchCall.Extent.Text)

    $AudioServiceRoot = $packageRoot
    $Workspace = $WorkspaceRoot
    Push-Location $packageRoot
    try {
        & $runAndroidPatch
        $patchedService = Get-Content -LiteralPath $serviceSource -Raw
        $patchedPlugin = Get-Content -LiteralPath $pluginSource -Raw
        if ($patchedService.Contains("customKeyCode") -or
            -not $patchedService.Contains("PendingIntent.FLAG_UPDATE_CURRENT")) {
            throw "PendingIntent patch did not change AudioService.java in the Git cache layout"
        }
        if (-not $patchedService.Contains("FOREGROUND_RECOVERY_TIMEOUT_MS") -or
            -not $patchedPlugin.Contains("pilimaxKeepForegroundDuringRecovery")) {
            throw "Foreground recovery patch did not change both Java sources in the Git cache layout"
        }
        $patchedHashes = @($serviceSource, $pluginSource) | Get-FileHash
        & $runAndroidPatch
        foreach ($patchedFile in $patchedHashes) {
            if ($patchedFile.Hash -ne (Get-FileHash -LiteralPath $patchedFile.Path).Hash) {
                throw "Repeated application changed $($patchedFile.Path)"
            }
        }
    } finally {
        Pop-Location
    }

    foreach ($patch in @($PendingIntentPatch, $ForegroundRecoveryPatch)) {
        & git -C $TemporaryRoot apply --ignore-space-change --directory=audio_service --reverse --check -- $patch
        if ($LASTEXITCODE -ne 0) { throw "Reverse patch validation failed: $patch" }
    }
    # The PendingIntent harness extracts the pre-recovery setState signature.
    & git -C $TemporaryRoot apply --ignore-space-change --directory=audio_service --reverse -- $ForegroundRecoveryPatch
    if ($LASTEXITCODE -ne 0) { throw "Unable to isolate the PendingIntent patch for its Java harness" }
    Invoke-ActualJavaRegression -Source (Get-Content -LiteralPath $serviceSource -Raw) -Name "patched"
    Write-Host "Both patches applied in the nested Git checkout and passed reverse and idempotence checks."
    Write-Host "Temporary fixture: $TemporaryRoot"
} finally {
    Pop-Location
}
