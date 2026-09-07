param(
    [switch]$NoDialog
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$clientDir = Join-Path $workspace 'client'
$serverDir = Join-Path $workspace 'server'
$serverExe = Join-Path $serverDir 'target\debug\cyberseeker-server.exe'
$logDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CyberSeeker\launcher'
$null = New-Item -ItemType Directory -Force -Path $logDir
$runId = [guid]::NewGuid().ToString('N').Substring(0, 12)
$mutex = New-Object Threading.Mutex($false, 'Local\CyberSeekerDesktopLauncher')
$locked = $false
$startedServer = $null

function Ready {
    try {
        $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/health' -TimeoutSec 2
        $ready = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/ready' -TimeoutSec 2
        return ($health.status -eq 'ok' -and $null -ne $health.configVersion -and
            $ready.status -eq 'ready' -and $ready.database -eq $true)
    } catch { return $false }
}

function Port-InUse {
    $probe = New-Object Net.Sockets.TcpClient
    try {
        $pending = $probe.BeginConnect('127.0.0.1', 8080, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne(300)) { return $false }
        $probe.EndConnect($pending)
        return $true
    } catch { return $false }
    finally { $probe.Dispose() }
}

try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { exit 0 }
    $godotPaths = @(
        (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe'),
        (Join-Path $workspace 'tools\Godot_v4.7.2-stable_win64.exe')
    )
    if ($env:CYBERSEEKER_GODOT) { $godotPaths = @($env:CYBERSEEKER_GODOT) + $godotPaths }
    $godot = $godotPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $godot) { throw 'Godot 4.7.2 introuvable. Le raccourci ne compile pas de version Android.' }
    if (-not (Test-Path -LiteralPath (Join-Path $clientDir 'project.godot'))) {
        throw 'Le dossier du jeu a ete deplace. Reinstaller le raccourci.'
    }

    if (-not (Ready)) {
        if (Port-InUse) {
            throw 'Le port 8080 est occupe mais le serveur du jeu ne repond pas correctement. Aucun processus existant ne sera ferme.'
        }
        if (-not (Test-Path -LiteralPath $serverExe -PathType Leaf)) {
            throw 'Le serveur local compile est absent. Demander a Codex de preparer le serveur desktop.'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $serverDir '.env') -PathType Leaf)) {
            throw 'Configuration locale server/.env absente. Aucun secret ni base de donnees ne sera cree automatiquement.'
        }
        # Process-local development settings: no .env changes, no wallet integration.
        $env:DEV_AUTH = 'true'
        $env:DEV_ADDRESS = 'dev-player-0001'
        $env:PORT = '8080'
        $env:CONFIG_DIR = Join-Path $workspace 'config'
        $env:RUST_LOG = 'info'
        $startedServer = Start-Process -FilePath $serverExe -WorkingDirectory $serverDir -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir "$runId-server.log") -RedirectStandardError (Join-Path $logDir "$runId-server.err.log")
        $deadline = [DateTime]::UtcNow.AddSeconds(35)
        do {
            if ($startedServer.HasExited) { throw 'Le serveur local a quitte. Verifier PostgreSQL et les logs du lanceur.' }
            if (Ready) { break }
            Start-Sleep -Milliseconds 350
        } while ([DateTime]::UtcNow -lt $deadline)
        if (-not (Ready)) { throw 'Le serveur local ne devient pas disponible. Verifier que PostgreSQL est demarre.' }
    }

    # Only reuse a game belonging to this exact checkout, never another Godot project/editor.
    $existing = Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" |
        Where-Object {
            $_.ExecutablePath -eq $godot -and
            $_.CommandLine -like "*$clientDir*" -and
            $_.CommandLine -notmatch '(?i)(--editor|\s-e(?:\s|$)|--headless|--script|res://tests/)'
        } | Select-Object -First 1
    if ($existing) {
        $desktopShell = New-Object -ComObject WScript.Shell
        $null = $desktopShell.AppActivate([int]$existing.ProcessId)
        Write-Output "GAME_ALREADY_RUNNING: $($existing.ProcessId)"
    } else {
        $env:CYBERSEEKER_API_URL = 'http://127.0.0.1:8080'
        # Visible game is explicitly requested; server/helper windows remain hidden.
        $game = Start-Process -FilePath $godot -WorkingDirectory $workspace -ArgumentList @('--path', ('"' + $clientDir + '"'), '--resolution', '540x960') -PassThru -RedirectStandardOutput (Join-Path $logDir "$runId-game.log") -RedirectStandardError (Join-Path $logDir "$runId-game.err.log")
        Start-Sleep -Milliseconds 1000
        if ($game.HasExited) { throw 'Godot a quitte au demarrage. Consulter les logs du lanceur.' }
        Write-Output "GAME_STARTED: $($game.Id)"
    }
    Write-Output "SERVER_READY: http://127.0.0.1:8080"
    Write-Output "LOGS: $logDir"
} catch {
    # Only stop a server created by this failed attempt, never a pre-existing one.
    if ($null -ne $startedServer -and -not $startedServer.HasExited) {
        Stop-Process -Id $startedServer.Id -ErrorAction SilentlyContinue
    }
    $message = $_.Exception.Message + [Environment]::NewLine + [Environment]::NewLine + 'Logs : ' + $logDir
    if (-not $NoDialog) {
        Add-Type -AssemblyName System.Windows.Forms
        $null = [Windows.Forms.MessageBox]::Show($message, 'CyberSeeker - lancement impossible', 'OK', 'Error')
    }
    Write-Error $message
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
