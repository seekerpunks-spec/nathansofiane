param(
    [string]$GodotPath = "",
    [string]$JavaHome = "",
    [string]$AndroidSdk = "",
    [string]$Output = ""
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$client = Join-Path $workspace "client"

if (-not $GodotPath) {
    $GodotPath = @(
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"),
        (Join-Path $env:USERPROFILE "Downloads\Godot_v4.7.2-stable_win64_console.exe")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}

if (-not $JavaHome) {
    $jdkRoot = Join-Path $env:LOCALAPPDATA "Programs\CyberSeekerJDK"
    $JavaHome = Get-ChildItem -LiteralPath $jdkRoot -Directory -Filter "jdk-17*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
}

if (-not $AndroidSdk) { $AndroidSdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
if (-not $Output) { $Output = Join-Path $client "build\android\CyberSeeker-debug.apk" }

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot console introuvable" }
if (-not (Test-Path -LiteralPath (Join-Path $JavaHome "bin\java.exe") -PathType Leaf)) { throw "JDK 17 introuvable" }
if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk "platform-tools") -PathType Container)) { throw "SDK Android introuvable" }
if (-not (Test-Path -LiteralPath (Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable\android_debug.apk") -PathType Leaf)) {
    throw "Template Android Godot 4.7.2 introuvable"
}

$buildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk "build-tools") -Directory |
    Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $buildTools) { throw "Android Build Tools introuvable" }

$env:JAVA_HOME = $JavaHome
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:ANDROID_HOME = $AndroidSdk
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null

& $GodotPath --headless --path $client --export-debug "Android" $Output
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Output -PathType Leaf)) {
    throw "Export APK Godot échoué"
}

& (Join-Path $buildTools "apksigner.bat") verify --verbose $Output
if ($LASTEXITCODE -ne 0) { throw "Signature APK invalide" }

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$badging = & (Join-Path $buildTools "aapt2.exe") dump badging $Output 2>&1 | Out-String
$aaptExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
if ($aaptExitCode -ne 0 -or $badging -notmatch "name='com\.cyberseeker\.game'") {
    throw "Manifest APK invalide"
}

$apk = Get-Item -LiteralPath $Output
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Output).Hash
Write-Host ("APK: {0} ({1:N1} Mio)" -f $apk.FullName, ($apk.Length / 1MB))
Write-Host "SHA256: $hash"
Write-Host "CYBERSEEKER_ANDROID_OK" -ForegroundColor Green
