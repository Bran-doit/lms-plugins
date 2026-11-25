param([Parameter(Mandatory=$true)][string]$ConfigPath)
. "$PSScriptRoot\DBRepair.Core.ps1"
$config = Read-JsonFile $ConfigPath
$queue = Assert-Child $config.CacheDir (Join-Path $config.CacheDir 'dbrepair')
$backups = Assert-PlainPath $config.BackupDir
$lock = $null
try {
    $lockPath = Assert-Child $queue (Join-Path $queue 'worker.lock')
    $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
} catch { exit 0 }
function Status($stage, $message) { Write-JsonFile (Join-Path $queue 'status.json') @{stage=$stage; message=$message; time=[DateTime]::UtcNow.ToString('o')} }
function Exists($name) { Test-Path -LiteralPath (Join-Path $queue $name) }
function Clear-Marker($name) {
    $p = Assert-Child $queue (Join-Path $queue $name)
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p }
}
function Assert-NoScanner {
    # Refuse to touch any database if an independent scanner is still alive.
    $scanners = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '^scanner(?:\.exe)?$' -or ($_.CommandLine -and $_.CommandLine -match '(?i)(?:^|[\\/\s"])scanner\.pl(?:["\s]|$)')
    })
    if ($scanners.Count) { throw 'Scanner laeuft noch. Reset abgebrochen; auf Scanende warten.' }
}
try {
    Write-JsonFile (Join-Path $queue 'heartbeat.json') @{time=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();version='0.7.0'}
    if (Exists 'working.json') { throw 'Ein vorheriger Auftrag wurde unterbrochen. working.json und Sicherungen vor Ort pruefen; kein automatischer Wiederholungsversuch.' }
    if (Exists 'scan.failed') {
        Status 'error' 'Datenbank zurueckgesetzt, aber Scanstart fehlgeschlagen. LMS-Scannerprotokoll pruefen und Scan manuell starten.'
        Clear-Marker 'scan.failed'; Clear-Marker 'scan.running'
    } elseif (Exists 'scan.finished') {
        Status 'finished' 'Datenbank zurueckgesetzt. LMS meldet den Scan als beendet. Titelzahl und Scannerprotokoll auf Importfehler pruefen.'
        Clear-Marker 'scan.finished'; Clear-Marker 'scan.running'
    } elseif (Exists 'scan.running') {
        Status 'scanning' 'Neuaufbau gestartet; warte auf LMS-Scanende. Bei ausbleibendem Abschluss Scannerprotokoll pruefen.'
    } elseif (Exists 'scan.pending') {
        Status 'waiting' 'Datenbank entfernt; warte auf Scanstart durch das DB-Repair-Plugin. Falls LMS nicht erreichbar wird, Dienst und Plugin vor Ort pruefen.'
    }
    Write-JsonFile (Join-Path $queue 'backups.json') @{items=@(Get-Backups $backups)}
    if (!(Exists 'request.json')) { return }
    if ((Exists 'scan.pending') -or (Exists 'scan.running')) { throw 'Neuaufbau noch aktiv; kein weiterer Auftrag erlaubt.' }
    $requestPath = Assert-Child $queue (Join-Path $queue 'request.json')
    $request = Read-JsonFile $requestPath
    if ($request.action -notin @('restart','reset','backup','delete')) { throw 'Unbekannter Auftrag.' }
    if ([Math]::Abs([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [double]$request.created) -gt 300) { throw 'Auftrag abgelaufen. request.json vor Ort pruefen und entfernen.' }
    [IO.File]::Move($requestPath, (Assert-Child $queue (Join-Path $queue 'working.json')))
    try {
        if ($request.action -eq 'delete') {
            Remove-Backup $backups $request.id
            Status 'deleted' 'Ausgewaehlte Sicherung endgueltig geloescht.'
        } elseif ($request.action -eq 'restart') {
            Assert-NoScanner
            $service = Get-Service -Name $config.ServiceName
            if ($service.Status -ne 'Running') { throw 'LMS-Dienst laeuft nicht. Neustart nicht gestartet.' }
            Status 'restarting' 'LMS wird neu gestartet. Wiedergabe und Oberflaeche werden kurz unterbrochen.'
            try {
                Stop-Service -Name $config.ServiceName -ErrorAction Stop
                $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
            } finally {
                Start-Service -Name $config.ServiceName -ErrorAction Stop
                $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
            }
            Status 'restarted' 'LMS-Dienst neu gestartet. Die Weboberflaeche wird wieder erreichbar, sobald LMS fertig gestartet ist.'
        } else {
            if ($request.action -eq 'reset') { Assert-Media $config }
            Assert-NoScanner
            $service = Get-Service -Name $config.ServiceName
            if ($service.Status -ne 'Running') { throw 'LMS-Dienst laeuft nicht. Reset nicht gestartet.' }
            $id = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
            Status 'stopping' 'LMS wird gestoppt. Wiedergabe und Oberflaeche werden unterbrochen.'
            try {
                Stop-Service -Name $config.ServiceName -ErrorAction Stop
                $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
                Assert-NoScanner
                # Also refuse surviving LMS processes, including non-service instances.
                $survivors = @(Get-CimInstance Win32_Process | Where-Object {
                    $_.Name -match '^(?:squeezeboxserver|slimserver|lyrionmusicserver)(?:\.exe)?$' -or ($_.CommandLine -and $_.CommandLine -match '(?i)(?:^|[\\/\s"])slimserver\.pl(?:["\s]|$)')
                })
                if ($survivors.Count) { throw 'LMS-Prozess noch aktiv. Keine Datenbank entfernt.' }
                if ($request.action -eq 'reset') { Assert-Media $config }
                $creationEvidence=@{observed_at=[DateTime]::UtcNow.ToString('o');service_name=$config.ServiceName;service_state=(Get-Service -Name $config.ServiceName).Status.ToString();scanner_absence_checked=$true;scanner_detection='Win32_Process scanner.exe / scanner.pl; also checks surviving LMS processes';helper_version='0.7.0';helper_pid=$PID}
                $creationContext=if($request.PSObject.Properties.Name -contains 'creation_context'){$request.creation_context}else{$null}
                $null = Move-DatabaseToBackup $config $backups $id $creationEvidence $creationContext -CopyOnly:($request.action -eq 'backup')
                if ($request.action -eq 'reset') {
                    Write-JsonFile (Join-Path $queue 'scan.pending') @{backup=$id; time=[DateTime]::UtcNow.ToString('o')}
                    Status 'starting' "Alte Datenbank gesichert ($id) und entfernt. LMS startet; vollstaendiger Scan folgt."
                }
            } finally {
                Start-Service -Name $config.ServiceName -ErrorAction Stop
                $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
            }
            if ($request.action -eq 'backup') { Status 'backed_up' "Datenbankkopie erstellt ($id). LMS arbeitet mit der bisherigen Datenbank weiter; kein Neuaufbau angefordert." }
        }
    } catch {
        Status 'error' $_.Exception.Message
    } finally {
        Clear-Marker 'working.json'
        Write-JsonFile (Join-Path $queue 'backups.json') @{items=@(Get-Backups $backups)}
    }
} catch {
    Status 'error' $_.Exception.Message
} finally {
    if ($lock) { $lock.Dispose() }
}
