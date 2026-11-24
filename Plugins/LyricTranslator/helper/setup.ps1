param([Parameter(Mandatory=$true)][string]$Root,[ValidateSet('auto','en','de','es','fr','it','pt','nl','ru')][string]$Source='en',[ValidateSet('en','de','es','fr','it','pt','nl','ru')][string]$Target='de',[ValidateSet('none','en','de','es','fr','it','pt','nl','ru')][string]$DetectedSource='none')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = [IO.Path]::GetFullPath($Root)
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Set-Status([string]$State, [string]$Code, [string]$Detail='') {
    $json = @{state=$State;code=$Code;detail=$Detail;source=$Source;target=$Target} | ConvertTo-Json -Compress
    $temporary = Join-Path $Root 'setup-status.json.tmp'
    [IO.File]::WriteAllText($temporary,$json,$utf8)
    Move-Item -LiteralPath $temporary -Destination (Join-Path $Root 'setup-status.json') -Force
}
try {
    if (-not [Environment]::Is64BitOperatingSystem) { throw 'Windows x64 is required.' }
    if ($Source -eq $Target) {throw 'Source and target must be different.'}
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $lockPath = Join-Path $Root 'setup.lock'
    $setupLock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $manifestPath = Join-Path $PSScriptRoot 'downloads.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Set-Status 'running' 'runtime'
    $downloads = Join-Path $Root 'downloads'
    $runtime = Join-Path $Root 'runtime'
    New-Item -ItemType Directory -Path $downloads,$runtime -Force | Out-Null
    $archive = Join-Path $downloads $manifest.python.filename
    if (-not (Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.python.sha256) {
        Invoke-WebRequest -UseBasicParsing -Uri $manifest.python.url -OutFile ($archive+'.download') -TimeoutSec 300
        if ((Get-FileHash -LiteralPath ($archive+'.download') -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.python.sha256) { throw 'Python checksum mismatch.' }
        Move-Item -LiteralPath ($archive+'.download') -Destination $archive -Force
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $runtime -Force
    # Keep Python private. No system PATH, registry or global package installation.
    [IO.File]::WriteAllText((Join-Path $runtime 'python311._pth'),"python311.zip`n.`nLib\site-packages`n$PSScriptRoot`nimport site`n",$utf8)
    $python = Join-Path $runtime 'python.exe'
    $bootstrap = Join-Path $PSScriptRoot 'bootstrap.py'
    & $python $bootstrap --root $Root --manifest $manifestPath --source $Source --target $Target --detected-source $DetectedSource *> (Join-Path $Root 'setup.log')
    if ($LASTEXITCODE -ne 0) { throw 'Setup failed. See setup-status.json and setup.log in the data folder.' }
} catch {
    # Preserve the more specific error written by bootstrap.py.
    $existing = $null
    try { $existing = Get-Content -LiteralPath (Join-Path $Root 'setup-status.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    if (-not $existing -or $existing.state -ne 'error') { Set-Status 'error' 'setup_error' $_.Exception.Message }
    exit 1
} finally {
    if ($setupLock) { $setupLock.Dispose() }
}
