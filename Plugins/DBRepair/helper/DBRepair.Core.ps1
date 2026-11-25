Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ServiceSid([string]$Account) {
    $name = $Account.Trim()
    # Win32_Service uses English service aliases even on localized Windows.
    # Resolve well-known accounts by SID, never by a translated display name.
    switch -Regex ($name) {
        '^(?i:LocalSystem|SYSTEM|NT AUTHORITY\\SYSTEM|NT-AUTORIT.T\\SYSTEM)$' { return [Security.Principal.SecurityIdentifier]::new('S-1-5-18') }
        '^(?i:LocalService|LOCAL SERVICE|NT AUTHORITY\\LocalService|NT AUTHORITY\\LOCAL SERVICE|NT-AUTORIT.T\\LOKALER DIENST)$' { return [Security.Principal.SecurityIdentifier]::new('S-1-5-19') }
        '^(?i:NetworkService|NETWORK SERVICE|NT AUTHORITY\\NetworkService|NT AUTHORITY\\NETWORK SERVICE|NT-AUTORIT.T\\NETZWERKDIENST)$' { return [Security.Principal.SecurityIdentifier]::new('S-1-5-20') }
    }
    if ($name -match '^S-1-\d+(?:-\d+)+$') { return [Security.Principal.SecurityIdentifier]::new($name) }
    if ($name.StartsWith('.\')) { $name = "$env:COMPUTERNAME\" + $name.Substring(2) }
    try {
        return ([Security.Principal.NTAccount]::new($name)).Translate([Security.Principal.SecurityIdentifier])
    } catch {
        throw "LMS-Dienstkonto '$Account' konnte nicht aufgeloest werden. Keine Ordnerrechte geaendert. Details: $($_.Exception.Message)"
    }
}
function New-PrivateAcl([Security.Principal.SecurityIdentifier]$ServiceSid) {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
        $identity = [Security.Principal.SecurityIdentifier]::new($sid)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    if ($ServiceSid -and $ServiceSid.Value -ne 'S-1-5-18') {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($ServiceSid,'Modify','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    return $acl
}

function Resolve-LmsServiceSid($Service) {
    # A running service's process token is authoritative, including accounts
    # renamed since the service was configured. Never guess a replacement user.
    if ($Service.State -eq 'Running' -and [uint32]$Service.ProcessId -gt 0) {
        $process = Get-CimInstance Win32_Process -Filter ('ProcessId = {0}' -f [uint32]$Service.ProcessId)
        if (!$process) { throw 'LMS-Dienstprozess verschwunden. Installation erneut versuchen.' }
        $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
        if ($owner.ReturnValue -ne 0 -or !$owner.Sid) { throw 'SID des laufenden LMS-Dienstes konnte nicht gelesen werden.' }
        $sid = [Security.Principal.SecurityIdentifier]::new($owner.Sid)
        Write-Verbose "LMS-Dienstkonto '$($Service.StartName)': Prozess-SID $($sid.Value)"
        return $sid
    }
    return Resolve-ServiceSid $Service.StartName
}

function Assert-PlainPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\')) { throw 'Nur lokale Pfade sind erlaubt.' }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Verknuepfung/Junction nicht erlaubt: $cursor" }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        $cursor = if ($parent) { $parent.FullName } else { $null }
    }
    return $full
}
function Assert-Child([string]$Root, [string]$Path) {
    $rootFull = (Assert-PlainPath $Root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $full = Assert-PlainPath $Path
    if (!$full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw "Pfad ausserhalb des erlaubten Ordners: $full" }
    return $full
}
function Write-JsonFile([string]$Path, $Value) {
    $null = Assert-PlainPath $Path
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, [NullString]::Value) }
    else { [IO.File]::Move($temp, $Path) }
}
function Read-JsonFile([string]$Path) {
    $null = Assert-PlainPath $Path
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Get-DatabaseFiles($Config) {
    $cache = Assert-PlainPath $Config.LibraryDir
    # Deliberately no wildcard deletion and no paths accepted from the web request.
    if ($Config.DatabaseName -ne 'library.db') { throw 'Diese Version unterstuetzt ausschliesslich library.db.' }
    if (Test-Path -LiteralPath (Join-Path $cache 'squeezebox.db')) { throw 'Alte squeezebox.db vorhanden: automatische LMS-Migration vor Reset klaeren.' }
    $names = @('library.db','library.db-wal','library.db-shm','library.db-journal')
    foreach ($name in $names) {
        $file = Assert-Child $cache (Join-Path $cache $name)
        if (Test-Path -LiteralPath $file) {
            if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Keine Datei: $file" }
            $file
        }
    }
}
function Assert-Media($Config) {
    if (@($Config.MediaDirs).Count -eq 0) { throw 'Keine Musikordner konfiguriert.' }
    foreach ($dir in $Config.MediaDirs) {
        if (!(Test-Path -LiteralPath $dir -PathType Container)) { throw "Musikordner nicht erreichbar: $dir" }
        # Enumerate as helper identity, not merely test the directory entry.
        $first = Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop | Select-Object -First 1
        if (!$first) { throw "Musikordner ist leer: $dir" }
    }
}
function Move-DatabaseToBackup($Config, [string]$BackupRoot, [string]$Id, $CreationEvidence = $null, $CreationContext = $null, [switch]$CopyOnly) {
    if ($Id -notmatch '^\d{8}T\d{6}-[a-f0-9]{8}$') { throw 'Ungueltige Sicherungs-ID.' }
    $destination = Assert-Child $BackupRoot (Join-Path $BackupRoot $Id)
    $files = @(Get-DatabaseFiles $Config)
    if (!(Test-Path -LiteralPath (Join-Path $Config.LibraryDir 'library.db') -PathType Leaf)) { throw 'library.db fehlt. Kein Reset ausgefuehrt.' }
    $null = New-Item -ItemType Directory -Path $destination -ErrorAction Stop
    $moved = @()
    try {
        foreach ($source in $files) {
            $target = Assert-Child $destination (Join-Path $destination ([IO.Path]::GetFileName($source)))
            if ($CopyOnly) { [IO.File]::Copy($source, $target, $false) }
            else { [IO.File]::Move($source, $target) }
            $moved += @{ source=$source; target=$target }
        }
        $fileEvidence=@($moved | ForEach-Object { @{name=[IO.Path]::GetFileName($_.target);bytes=(Get-Item -LiteralPath $_.target).Length;sha256=(Get-FileHash -LiteralPath $_.target -Algorithm SHA256).Hash.ToLower()} })
        Write-JsonFile (Join-Path $destination 'manifest.json') @{
            format_version=2;id=$Id; files=@($moved | ForEach-Object { [IO.Path]::GetFileName($_.target) }); created=[DateTime]::UtcNow.ToString('o');
            method=$(if($CopyOnly){'copy_with_service_stopped'}else{'same_volume_move_with_service_stopped'});file_evidence=$fileEvidence;creation_evidence=$CreationEvidence;creation_context=$CreationContext;
            context_timing='LMS context captured when operation requested, before service stop; see captured_epoch. Service/scanner evidence captured separately immediately before file operation.';
            sidecar_policy='Existing library.db-wal, library.db-shm and library.db-journal preserved intact with library.db; no extra checkpoint/commit. Missing sidecars are listed as absent.';
            absent_sidecars=@('library.db-wal','library.db-shm','library.db-journal' | Where-Object {$_ -notin $fileEvidence.name})
        }
    } catch {
        $failure = $_
        if ($CopyOnly) {
            # Only this newly created, validated backup directory is cleaned.
            Remove-Backup $BackupRoot $Id
        } else { foreach ($entry in $moved) { [IO.File]::Move($entry.target, $entry.source) } }
        throw $failure
    }
    return $destination
}
function Remove-Backup([string]$BackupRoot, [string]$Id) {
    if ($Id -notmatch '^\d{8}T\d{6}-[a-f0-9]{8}$') { throw 'Ungueltige Sicherungs-ID.' }
    $target = Assert-Child $BackupRoot (Join-Path $BackupRoot $Id)
    if (!(Test-Path -LiteralPath $target -PathType Container)) { throw 'Sicherung nicht gefunden.' }
    $items = @(Get-ChildItem -LiteralPath $target -Force)
    foreach ($item in $items) {
        $null = Assert-Child $target $item.FullName
        if ($item.PSIsContainer -or $item.Name -notin @('library.db','library.db-wal','library.db-shm','library.db-journal','manifest.json')) { throw 'Unerwarteter Inhalt in Sicherung. Loeschen abgebrochen.' }
    }
    foreach ($item in $items) { Remove-Item -LiteralPath $item.FullName -Force }
    Remove-Item -LiteralPath $target -Force
}
function Get-Backups([string]$BackupRoot) {
    foreach ($dir in Get-ChildItem -LiteralPath $BackupRoot -Directory) {
        if ($dir.Name -match '^\d{8}T\d{6}-[a-f0-9]{8}$') {
            $null = Assert-Child $BackupRoot $dir.FullName
            $bytes = (Get-ChildItem -LiteralPath $dir.FullName -File | Measure-Object Length -Sum).Sum
            @{ id=$dir.Name; bytes=$bytes }
        }
    }
}
