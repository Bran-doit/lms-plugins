. "$PSScriptRoot\..\Plugins\DBRepair\helper\DBRepair.Core.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dbrepair-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot
$cache = Join-Path $testRoot 'cache'
$backups = Join-Path $testRoot 'backups'
$media = Join-Path $testRoot 'music'
foreach ($p in @($cache,$backups,$media)) { $null = New-Item -ItemType Directory -Path $p }
$config = @{CacheDir=$cache; LibraryDir=$cache; DatabaseName='library.db'; MediaDirs=@($media)}
$script:checks = 0
function Check($condition,$message) { if (!$condition) { throw "FAIL: $message" }; $script:checks++; Write-Output "PASS: $message" }
function Reject([scriptblock]$action, $message) { $failed=$false; try { & $action } catch { $failed=$true }; Check $failed $message }
try {
    Reject { Assert-Media $config } 'Empty media refuses reset'
    [IO.File]::WriteAllText((Join-Path $media 'song.flac'),'music')
    Assert-Media $config
    Check $true 'Readable media accepted'
    foreach ($name in @('library.db','library.db-wal','library.db-shm','library.db-journal','persist.db','artwork.db')) {
        [IO.File]::WriteAllText((Join-Path $cache $name),$name)
    }
    $id='20261110T120000-12345678'
    $backup = Move-DatabaseToBackup $config $backups $id
    Check (!(Test-Path -LiteralPath (Join-Path $cache 'library.db'))) 'Active database removed'
    Check ((Get-Content -LiteralPath (Join-Path $backup 'library.db') -Raw) -eq 'library.db') 'Backup content preserved'
    Check ((Get-ChildItem -LiteralPath $backup -File).Count -eq 5) 'All SQLite sidecars and manifest preserved'
    $manifest=Read-JsonFile (Join-Path $backup 'manifest.json')
    Check ($manifest.format_version -eq 2) 'Backup evidence manifest version recorded'
    Check ($manifest.file_evidence.Count -eq 4) 'All moved database and sidecar files documented'
    Check ($manifest.file_evidence[0].sha256 -match '^[a-f0-9]{64}$') 'SHA256 recorded for backup file'
    Check ($null -eq $manifest.creation_evidence) 'Direct test move does not invent stopped-service evidence'
    Check (Test-Path -LiteralPath (Join-Path $cache 'persist.db')) 'Persistent statistics untouched'
    Check (Test-Path -LiteralPath (Join-Path $cache 'artwork.db')) 'Other caches untouched'
    Check ((@(Get-Backups $backups)).Count -eq 1) 'Backup catalog contains saved database'
    Reject { Remove-Backup $backups '..\cache' } 'Traversal rejected'
    Reject { Assert-Child $cache (Join-Path $testRoot 'cache-other\file') } 'Sibling prefix rejected'
    $unexpected=Join-Path $backup 'unknown.txt'
    [IO.File]::WriteAllText($unexpected,'keep')
    Reject { Remove-Backup $backups $id } 'Unexpected backup contents block deletion'
    Check (Test-Path -LiteralPath (Join-Path $backup 'library.db')) 'Rejected deletion preserves backup'
    Remove-Item -LiteralPath $unexpected
    Remove-Backup $backups $id
    Check (!(Test-Path -LiteralPath $backup)) 'Selected backup deleted'
    Check (Test-Path -LiteralPath (Join-Path $media 'song.flac')) 'Music untouched'
    Reject { Move-DatabaseToBackup $config $backups '20261110T120001-12345678' } 'Missing active database rejected'
    [IO.File]::WriteAllText((Join-Path $cache 'library.db'),'original')
    [IO.File]::WriteAllText((Join-Path $cache 'library.db-wal'),'wal')
    $locked = [IO.File]::Open((Join-Path $cache 'library.db-wal'),'Open','ReadWrite','None')
    try { Reject { Move-DatabaseToBackup $config $backups '20261110T120002-12345678' } 'Locked sidecar aborts operation' } finally { $locked.Dispose() }
    Check ((Get-Content -LiteralPath (Join-Path $cache 'library.db') -Raw) -eq 'original') 'Partial move rolls database back'
    Check ((Get-Content -LiteralPath (Join-Path $cache 'library.db-wal') -Raw) -eq 'wal') 'Failed reset preserves WAL'
    $locked = [IO.File]::Open((Join-Path $cache 'library.db-wal'),'Open','ReadWrite','None')
    try { Reject { Move-DatabaseToBackup $config $backups '20261110T120003-12345678' -CopyOnly } 'Locked sidecar aborts copy' } finally { $locked.Dispose() }
    Check ((Get-Content -LiteralPath (Join-Path $cache 'library.db') -Raw) -eq 'original') 'Failed copy preserves original'
    Check (!(Test-Path -LiteralPath (Join-Path $backups '20261110T120003-12345678'))) 'Failed copy is not offered as backup'
    Write-JsonFile (Join-Path $cache 'test.json') @{message='first'}
    Write-JsonFile (Join-Path $cache 'test.json') @{message='second'}
    Check ((Read-JsonFile (Join-Path $cache 'test.json')).message -eq 'second') 'Atomic status replacement'
    [IO.File]::WriteAllText((Join-Path $cache 'squeezebox.db'),'legacy')
    Reject { Get-DatabaseFiles $config } 'Legacy database migration blocks reset'
    $parseErrors = @()
    Get-ChildItem "$PSScriptRoot\..\Plugins\DBRepair\helper" -Filter '*.ps1' | ForEach-Object {
        $tokens=$null; $errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
        $parseErrors += $errors
    }
    Check ($parseErrors.Count -eq 0) 'All PowerShell scripts parse'
    Write-Output "$script:checks checks passed."
} finally {
    # Only delete our freshly generated, validated temporary test directory.
    $verified = Assert-Child ([IO.Path]::GetTempPath()) $testRoot
    if ([IO.Path]::GetFileName($verified) -notmatch '^dbrepair-test-[a-f0-9]{32}$') { throw 'Invalid cleanup path' }
    Remove-Item -LiteralPath $verified -Recurse -Force
}
