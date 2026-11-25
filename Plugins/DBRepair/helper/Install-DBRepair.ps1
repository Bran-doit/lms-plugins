# Run elevated ON THE LMS SERVER. Installs the helper only, not a database reset.
#requires -RunAsAdministrator
param(
    [Parameter(Mandatory=$true)][string]$ServiceName,
    [Parameter(Mandatory=$true)][string]$CacheDir,
    [string]$LibraryDir,
    [Parameter(Mandatory=$true)][string[]]$MediaDirs,
    [string]$InstallDir = "$env:ProgramFiles\DB Repair",
    [string]$BackupDir,
    [switch]$ReplaceExisting
)
. "$PSScriptRoot\DBRepair.Core.ps1"
$CacheDir = Assert-PlainPath $CacheDir
if (!$LibraryDir) { $LibraryDir = $CacheDir }
$LibraryDir = Assert-PlainPath $LibraryDir
$InstallDir = Assert-PlainPath $InstallDir
if (!$BackupDir) { $BackupDir = Join-Path ([IO.Path]::GetPathRoot($LibraryDir)) 'DBRepair-Backups' }
$BackupDir = Assert-PlainPath $BackupDir
if ([IO.Path]::GetPathRoot($LibraryDir) -ne [IO.Path]::GetPathRoot($BackupDir)) { throw 'Sicherungen muessen fuer atomisches Verschieben auf demselben Laufwerk liegen.' }
if ($BackupDir.TrimEnd('\') -eq $CacheDir.TrimEnd('\') -or $BackupDir.StartsWith($CacheDir.TrimEnd('\')+'\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Sicherungsordner muss ausserhalb des LMS-Cache liegen.' }
if ($BackupDir.TrimEnd('\') -eq $LibraryDir.TrimEnd('\') -or $BackupDir.StartsWith($LibraryDir.TrimEnd('\')+'\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Sicherungsordner muss ausserhalb des Bibliotheksordners liegen.' }
if (!(Test-Path -LiteralPath (Join-Path $LibraryDir 'library.db') -PathType Leaf)) { throw 'Im angegebenen Bibliotheksordner liegt keine library.db.' }
$service = Get-CimInstance Win32_Service | Where-Object { $_.Name -eq $ServiceName }
if (!$service) { throw 'Windows-Dienst nicht gefunden.' }
$serviceSid = Resolve-LmsServiceSid $service
# Build both ACLs before creating folders or changing any permissions.
$privateAcl = New-PrivateAcl
$queueAcl = New-PrivateAcl $serviceSid
if ($service.PathName -notmatch '(?i)squeezebox|slimserver|lyrion|sqzsvc') { throw 'Dienst ist nicht als LMS erkennbar; Konfiguration vor Ort pruefen.' }
if ((Test-Path -LiteralPath $InstallDir) -and !$ReplaceExisting) { throw 'Installationsordner existiert. Fuer ein bewusstes Update -ReplaceExisting verwenden.' }
if (Get-ScheduledTask -TaskName 'DB Repair Worker' -ErrorAction SilentlyContinue) {
    if (!$ReplaceExisting) { throw 'Aufgabe existiert bereits.' }
    if ((Get-ScheduledTask -TaskName 'DB Repair Worker').State -eq 'Running') { throw 'Helfer laeuft noch. Update spaeter versuchen.' }
}
$config = @{ServiceName=$ServiceName; CacheDir=$CacheDir; LibraryDir=$LibraryDir; DatabaseName='library.db'; BackupDir=$BackupDir; MediaDirs=$MediaDirs}
Assert-Media $config
$queue = Assert-Child $CacheDir (Join-Path $CacheDir 'dbrepair')
foreach ($dir in @($InstallDir,$BackupDir,$queue)) {
    if (!(Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir }
}
# The privileged task's code/configuration and backups are NOT writable by LMS.
Set-Acl -LiteralPath $InstallDir -AclObject $privateAcl
Set-Acl -LiteralPath $BackupDir -AclObject $privateAcl
Set-Acl -LiteralPath $queue -AclObject $queueAcl
foreach ($name in @('DBRepair.Core.ps1','DBRepair.Worker.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $InstallDir $name) -Force
}
$configPath = Join-Path $InstallDir 'config.json'
Write-JsonFile $configPath $config
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -ConfigPath "{1}"' -f (Join-Path $InstallDir 'DBRepair.Worker.ps1'), $configPath)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -StartWhenAvailable
$null = Register-ScheduledTask -TaskName 'DB Repair Worker' -Action $action -Trigger $trigger -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force
Start-ScheduledTask -TaskName 'DB Repair Worker'
Write-Output "DB Repair Helfer installiert. Warteschlange: $queue. Es wurde KEIN Reset gestartet."
Write-Output 'Bei Netzlaufwerken: SYSTEM muss die UNC-Musikpfade lesen koennen; gemappte Laufwerksbuchstaben vermeiden.'
