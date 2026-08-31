param(
    [string]$GodotPath = "",
    [string]$TestDatabaseUrl = "postgres://postgres:postgres@localhost:5432/cyberseeker_test",
    [string]$CargoTargetDir = "",
    [int]$PrimaryPort = 18084,
    [int]$SecondaryPort = 18085
)

$ErrorActionPreference = "Stop"
$workspace = Split-Path -Parent $PSScriptRoot
$serverDir = Join-Path $workspace "server"
$configDir = Join-Path $workspace "config"
$validateScript = Join-Path $PSScriptRoot "validate_all.ps1"
$runId = [guid]::NewGuid().ToString("N").Substring(0, 12)
$alphaAddress = "gate-alpha-$runId"
$betaAddress = "gate-beta-$runId"
$jwtSecret = "local-full-gate-$([guid]::NewGuid().ToString('N'))"
$primaryBaseUrl = "http://127.0.0.1:$PrimaryPort"
$secondaryBaseUrl = "http://127.0.0.1:$SecondaryPort"
$primaryProcess = $null
$secondaryProcess = $null
$succeeded = $false
$tempRoot = [System.IO.Path]::GetTempPath()
$primaryOut = Join-Path $tempRoot "cyberseeker-gate-$runId-primary.out.log"
$primaryErr = Join-Path $tempRoot "cyberseeker-gate-$runId-primary.err.log"
$secondaryOut = Join-Path $tempRoot "cyberseeker-gate-$runId-secondary.out.log"
$secondaryErr = Join-Path $tempRoot "cyberseeker-gate-$runId-secondary.err.log"

if ($PrimaryPort -lt 1024 -or $PrimaryPort -gt 65535 -or
    $SecondaryPort -lt 1024 -or $SecondaryPort -gt 65535 -or
    $PrimaryPort -eq $SecondaryPort) {
    throw "ports invalides ou identiques"
}

function Test-TcpPort([int]$Port) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $result = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne(250)) { return $false }
        try {
            $client.EndConnect($result)
            return $client.Connected
        } catch {
            return $false
        }
    } finally {
        $client.Dispose()
    }
}

function Wait-Ready(
    [System.Diagnostics.Process]$Process,
    [string]$BaseUrl,
    [string]$ErrorLog,
    [string]$Name
) {
    for ($attempt = 0; $attempt -lt 80; $attempt++) {
        if ($Process.HasExited) {
            $tail = if (Test-Path -LiteralPath $ErrorLog) {
                (Get-Content -Encoding UTF8 -LiteralPath $ErrorLog -Tail 80) -join [Environment]::NewLine
            } else { "journal absent" }
            throw "$Name s'est arrêté avant readiness (code $($Process.ExitCode))`n$tail"
        }
        try {
            $ready = Invoke-RestMethod -Uri ($BaseUrl + "/ready") -TimeoutSec 1
            if ($ready.status -eq "ready" -and $ready.database -eq $true) { return }
        } catch { }
        Start-Sleep -Milliseconds 250
    }
    $tail = if (Test-Path -LiteralPath $ErrorLog) {
        (Get-Content -Encoding UTF8 -LiteralPath $ErrorLog -Tail 80) -join [Environment]::NewLine
    } else { "journal absent" }
    throw "$Name n'est pas ready après 20 secondes`n$tail"
}

function Set-ProcessEnvironment([hashtable]$Values) {
    foreach ($entry in $Values.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, "Process")
    }
}

function Stop-OwnedProcess([System.Diagnostics.Process]$Process) {
    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -ErrorAction Stop
            [void]$Process.WaitForExit(5000)
        }
    } catch {
        Write-Warning "arrêt du processus $($Process.Id) incomplet : $($_.Exception.Message)"
    }
}

if (Test-TcpPort $PrimaryPort) { throw "port $PrimaryPort déjà occupé" }
if (Test-TcpPort $SecondaryPort) { throw "port $SecondaryPort déjà occupé" }

$cargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
if (-not (Test-Path -LiteralPath $cargo)) {
    $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargoCommand) { throw "cargo introuvable" }
    $cargo = $cargoCommand.Source
}
if (-not $CargoTargetDir) {
    $CargoTargetDir = if ($env:CARGO_TARGET_DIR) {
        $env:CARGO_TARGET_DIR
    } else {
        Join-Path $serverDir "target"
    }
}
# Cargo résout un target relatif depuis son répertoire de travail (`server/`).
# Figer le chemin absolu avant le build garantit que la recherche/lancement du
# binaire utilise exactement le même emplacement après Pop-Location.
if (-not [System.IO.Path]::IsPathRooted($CargoTargetDir)) {
    $CargoTargetDir = Join-Path $serverDir $CargoTargetDir
}
$CargoTargetDir = [System.IO.Path]::GetFullPath($CargoTargetDir)
$serverExe = Join-Path $CargoTargetDir "debug\cyberseeker-server.exe"

$environmentNames = @(
    "CARGO_TARGET_DIR", "DATABASE_URL", "JWT_SECRET", "DEV_AUTH",
    "DEV_ADDRESS", "PORT", "CONFIG_DIR", "RATE_LIMIT_PER_MINUTE", "RUST_LOG",
    "CYBERSEEKER_TEST_DATABASE_URL", "CYBERSEEKER_ALLOW_DB_TEST_SKIP"
)
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
    [Environment]::SetEnvironmentVariable("CARGO_TARGET_DIR", $CargoTargetDir, "Process")
    Push-Location $serverDir
    try {
        & $cargo build --bin cyberseeker-server
        if ($LASTEXITCODE -ne 0) { throw "build debug serveur échoué" }
    } finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
        throw "binaire serveur absent après build : $serverExe"
    }

    $sharedEnvironment = @{
        DATABASE_URL = $TestDatabaseUrl
        JWT_SECRET = $jwtSecret
        DEV_AUTH = "true"
        CONFIG_DIR = $configDir
        RATE_LIMIT_PER_MINUTE = "1000"
        RUST_LOG = "info"
    }
    Set-ProcessEnvironment $sharedEnvironment

    [Environment]::SetEnvironmentVariable("PORT", [string]$PrimaryPort, "Process")
    [Environment]::SetEnvironmentVariable("DEV_ADDRESS", $alphaAddress, "Process")
    $primaryProcess = Start-Process -FilePath $serverExe -WorkingDirectory $serverDir `
        -WindowStyle Hidden -RedirectStandardOutput $primaryOut `
        -RedirectStandardError $primaryErr -PassThru

    [Environment]::SetEnvironmentVariable("PORT", [string]$SecondaryPort, "Process")
    [Environment]::SetEnvironmentVariable("DEV_ADDRESS", $betaAddress, "Process")
    $secondaryProcess = Start-Process -FilePath $serverExe -WorkingDirectory $serverDir `
        -WindowStyle Hidden -RedirectStandardOutput $secondaryOut `
        -RedirectStandardError $secondaryErr -PassThru

    Wait-Ready $primaryProcess $primaryBaseUrl $primaryErr "instance primaire"
    Wait-Ready $secondaryProcess $secondaryBaseUrl $secondaryErr "instance secondaire"
    Write-Host "Deux instances DEV prêtes : $PrimaryPort / $SecondaryPort" -ForegroundColor Cyan

    $validationArguments = @{
        ApiBaseUrl = $primaryBaseUrl
        ApiSecondaryAuthBaseUrl = $secondaryBaseUrl
        ApiDevAddress = $alphaAddress
        ApiSecondaryDevAddress = $betaAddress
        TestDatabaseUrl = $TestDatabaseUrl
    }
    if ($GodotPath) { $validationArguments["GodotPath"] = $GodotPath }
    & $validateScript @validationArguments
    if ($LASTEXITCODE -ne 0) { throw "validation locale complète échouée" }
    $succeeded = $true
    Write-Host "LOCAL_FULL_GATE_OK" -ForegroundColor Green
} finally {
    Stop-OwnedProcess $secondaryProcess
    Stop-OwnedProcess $primaryProcess
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], "Process")
    }
    if ($succeeded) {
        foreach ($log in @($primaryOut, $primaryErr, $secondaryOut, $secondaryErr)) {
            if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
        }
    } else {
        Write-Warning "journaux conservés : $primaryOut ; $primaryErr ; $secondaryOut ; $secondaryErr"
    }
}
