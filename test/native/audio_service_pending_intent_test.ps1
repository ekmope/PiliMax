param(
    [string]$AudioServicePackageRoot = "",
    [string]$JavaHome = ""
)

$ErrorActionPreference = "Stop"
$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$PatchPath = Join-Path $WorkspaceRoot "lib/scripts/audio_service_pending_intent.patch"
$RelativeSource = "android/src/main/java/com/ryanheise/audioservice/AudioService.java"
if ([string]::IsNullOrWhiteSpace($AudioServicePackageRoot)) {
    $config = Get-Content (Join-Path $WorkspaceRoot ".dart_tool/package_config.json") -Raw | ConvertFrom-Json
    $package = $config.packages | Where-Object name -eq "audio_service" | Select-Object -First 1
    if ($null -eq $package) { throw "audio_service is missing from package_config.json" }
    $AudioServicePackageRoot = ([Uri]$package.rootUri).LocalPath
}
$OriginalSourcePath = Join-Path $AudioServicePackageRoot $RelativeSource
if (-not (Test-Path $OriginalSourcePath)) { throw "AudioService.java not found: $OriginalSourcePath" }
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
    $sourceDirectory = Split-Path $OriginalSourcePath
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
    $temporarySource = Join-Path $TemporaryRoot $RelativeSource
    New-Item -ItemType Directory -Path (Split-Path $temporarySource) -Force | Out-Null
    Copy-Item -LiteralPath $OriginalSourcePath -Destination $temporarySource
    & git init -q
    if ($LASTEXITCODE -ne 0) { throw "Unable to create isolated patch fixture" }
    # Accept an already patched dependency, but normalize only the temporary copy.
    & git apply --ignore-space-change --reverse --check -- $PatchPath *> $null
    if ($LASTEXITCODE -eq 0) {
        & git apply --ignore-space-change --reverse -- $PatchPath
        if ($LASTEXITCODE -ne 0) { throw "Unable to normalize temporary fixture" }
    }
    $unpatched = Get-Content $temporarySource -Raw
    Invoke-ActualJavaRegression -Source $unpatched -Name "unpatched" -ExpectFailure $true

    # Run the real CI helper, without executing pub get or SDK patch/reset code.
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $WorkspaceRoot "lib/scripts/patch.ps1"), [ref]$null, [ref]$parseErrors
    )
    if ($parseErrors.Count) { throw "patch.ps1 has parse errors" }
    $helper = $ast.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq "Apply-DependencyPatch"
    }, $true)
    if ($null -eq $helper) { throw "CI dependency-patch helper not found" }
    . ([ScriptBlock]::Create($helper.Extent.Text))
    if (-not (Apply-DependencyPatch -PatchPath $PatchPath -Description "AudioService PendingIntent regression fixture")) {
        throw "Forward patch application failed"
    }
    $patchedHash = (Get-FileHash -LiteralPath $temporarySource).Hash
    if (-not (Apply-DependencyPatch -PatchPath $PatchPath -Description "AudioService PendingIntent regression fixture")) {
        throw "Idempotent patch application failed"
    }
    if ($patchedHash -ne (Get-FileHash -LiteralPath $temporarySource).Hash) {
        throw "Repeated application changed the dependency"
    }
    & git apply --ignore-space-change --reverse --check -- $PatchPath
    if ($LASTEXITCODE -ne 0) { throw "Reverse patch validation failed" }
    Invoke-ActualJavaRegression -Source (Get-Content $temporarySource -Raw) -Name "patched"
    Write-Host "Patch forward/reverse/idempotence and actual Java-method regression passed."
    Write-Host "Temporary fixture: $TemporaryRoot"
} finally {
    Pop-Location
}
