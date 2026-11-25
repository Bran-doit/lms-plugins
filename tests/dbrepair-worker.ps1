. "$PSScriptRoot\..\Plugins\DBRepair\helper\DBRepair.Core.ps1"
$root=Join-Path ([IO.Path]::GetTempPath()) ('dbrepair-test-'+[guid]::NewGuid().ToString('N'))
$cache=Join-Path $root 'cache'; $queue=Join-Path $cache 'dbrepair'; $backup=Join-Path $root 'backups'; $media=Join-Path $root 'music'
foreach($p in @($root,$cache,$queue,$backup,$media)){ $null=New-Item -ItemType Directory -Path $p }
$configPath=Join-Path $root 'config.json'
Write-JsonFile $configPath @{ServiceName='TEST-ONLY';CacheDir=$cache;LibraryDir=$cache;BackupDir=$backup;DatabaseName='library.db';MediaDirs=@($media)}
[IO.File]::WriteAllText((Join-Path $media 'track.flac'),'music')
$global:dbRepairTest=@{};$global:dbRepairTest.starts=0;$global:dbRepairTest.stops=0;$global:dbRepairTest.scanner=$false;$global:dbRepairTest.stopFailure=$false;$script:checks=0
# ALL service/process access is mocked. No Windows service is touched.
function Get-Service { param($Name) if($Name -ne 'TEST-ONLY'){throw 'Unexpected service'}; $s=[pscustomobject]@{Status='Running'}; $s | Add-Member ScriptMethod WaitForStatus {}; return $s }
function Stop-Service { param($Name,$ErrorAction) $global:dbRepairTest.stops++; if($global:dbRepairTest.stopFailure){throw 'Simulated stop failure'} }
function Start-Service { param($Name,$ErrorAction) $global:dbRepairTest.starts++ }
function Get-CimInstance { param($ClassName) if($global:dbRepairTest.scanner){[pscustomobject]@{Name='scanner.exe';CommandLine='scanner.exe'}} }
function Run { & "$PSScriptRoot\..\Plugins\DBRepair\helper\DBRepair.Worker.ps1" -ConfigPath $configPath }
function Request($action,$id='') { Write-JsonFile (Join-Path $queue 'request.json') @{action=$action;id=$id;created=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()} }
function Check($condition,$message){if(!$condition){throw "FAIL: $message"};$script:checks++;Write-Output "PASS: $message"}
try {
    [IO.File]::WriteAllText((Join-Path $cache 'library.db'),'original')
    Run
    Check ($global:dbRepairTest.stops -eq 0) 'Idle worker does not stop LMS'
    Request 'reset';$global:dbRepairTest.scanner=$true;Run;$global:dbRepairTest.scanner=$false
    Check ($global:dbRepairTest.stops -eq 0) 'Independent scanner prevents service stop'
    Check (Test-Path -LiteralPath (Join-Path $cache 'library.db')) 'Scanner conflict preserves active database'
    Request 'reset';$global:dbRepairTest.stopFailure=$true;Run;$global:dbRepairTest.stopFailure=$false
    Check (Test-Path -LiteralPath (Join-Path $cache 'library.db')) 'Stop failure preserves database'
    Write-Output ((Read-JsonFile (Join-Path $queue 'status.json')) | ConvertTo-Json)
    Check ($global:dbRepairTest.starts -eq 1) 'Service restart attempted after stop failure'
    Request 'reset';Run
    Check (!(Test-Path -LiteralPath (Join-Path $cache 'library.db'))) 'Worker removes active database'
    Check (Test-Path -LiteralPath (Join-Path $queue 'scan.pending')) 'Scan marker survives service restart'
    Check ($global:dbRepairTest.starts -eq 2) 'Service restarted after reset'
    $catalog=Read-JsonFile (Join-Path $queue 'backups.json')
    Check (@($catalog.items).Count -eq 1) 'Worker publishes backup catalog'
    Remove-Item -LiteralPath (Join-Path $queue 'scan.pending')
    Write-JsonFile (Join-Path $queue 'scan.running') @{}
    Write-JsonFile (Join-Path $queue 'scan.finished') @{}
    Run
    Check ((Read-JsonFile (Join-Path $queue 'status.json')).stage -eq 'finished') 'Scan completion shown'
    Check (!(Test-Path -LiteralPath (Join-Path $queue 'scan.running'))) 'Scan lock cleared after completion'
    Request 'delete' $catalog.items[0].id;Run
    Check (@((Read-JsonFile (Join-Path $queue 'backups.json')).items).Count -eq 0) 'Deletion request removes selected backup'
    Check ($global:dbRepairTest.starts -eq 2) 'Backup deletion needs no restart'
    [IO.File]::WriteAllText((Join-Path $cache 'library.db'),'restart-must-preserve')
    Request 'restart';Run
    Check ($global:dbRepairTest.starts -eq 3) 'Restart action starts service exactly once'
    Check ((Get-Content -LiteralPath (Join-Path $cache 'library.db') -Raw) -eq 'restart-must-preserve') 'Restart preserves active database bytes'
    Check (!(Test-Path -LiteralPath (Join-Path $queue 'scan.pending'))) 'Restart does not schedule a rescan'
    Check ((Read-JsonFile (Join-Path $queue 'status.json')).stage -eq 'restarted') 'Restart completion reported'
    Run
    Check ($global:dbRepairTest.starts -eq 3) 'Completed restart is not repeated'
    [IO.File]::WriteAllText((Join-Path $cache 'library.db-wal'),'wal-evidence')
    Request 'backup';Run
    Check ($global:dbRepairTest.starts -eq 4) 'Backup restarts service once'
    Check ((Get-Content -LiteralPath (Join-Path $cache 'library.db') -Raw) -eq 'restart-must-preserve') 'Backup preserves active database'
    Check ((Get-Content -LiteralPath (Join-Path $cache 'library.db-wal') -Raw) -eq 'wal-evidence') 'Backup preserves active WAL'
    Check (!(Test-Path -LiteralPath (Join-Path $queue 'scan.pending'))) 'Backup never requests rebuild'
    Check ((Read-JsonFile (Join-Path $queue 'status.json')).stage -eq 'backed_up') 'Backup completion reported'
    $catalog=Read-JsonFile (Join-Path $queue 'backups.json')
    $copy=Join-Path $backup $catalog.items[0].id
    Check ((Get-Content -LiteralPath (Join-Path $copy 'library.db') -Raw) -eq 'restart-must-preserve') 'Catalog backup contains current data'
    Check ((Get-Content -LiteralPath (Join-Path $copy 'library.db-wal') -Raw) -eq 'wal-evidence') 'Catalog backup contains WAL'
    Check ((Read-JsonFile (Join-Path $copy 'manifest.json')).method -eq 'copy_with_service_stopped') 'Manifest distinguishes copy from reset'
    Write-JsonFile (Join-Path $queue 'working.json') @{action='reset'}
    Request 'reset';Run
    Check ((Read-JsonFile (Join-Path $queue 'status.json')).stage -eq 'error') 'Interrupted job requires manual inspection'
    Check ($global:dbRepairTest.starts -eq 4) 'Interrupted reset is not replayed'
    Write-Output "$script:checks checks passed."
} finally {
    $verified=Assert-Child ([IO.Path]::GetTempPath()) $root
    if([IO.Path]::GetFileName($verified) -notmatch '^dbrepair-test-[a-f0-9]{32}$'){throw 'Invalid test cleanup'}
    Remove-Item -LiteralPath $verified -Recurse -Force
}

