#requires -RunAsAdministrator
param([switch]$ReplaceExisting, [switch]$RestartLms)
$ErrorActionPreference='Stop'
$services = @(Get-CimInstance Win32_Service | Where-Object { $_.PathName -match '(?i)squeezebox|slimserver|lyrion|sqzsvc' })
if ($services.Count -ne 1) { throw 'LMS-Dienst nicht eindeutig. Install-DBRepair.ps1 mit explizitem Dienstnamen verwenden.' }
function Read-LmsPreference($name) {
    $body=@{id=1;method='slim.request';params=@('',@('pref',$name,'?'))} | ConvertTo-Json -Depth 5
    $response=Invoke-RestMethod 'http://127.0.0.1:9000/jsonrpc.js' -Method Post -ContentType 'application/json' -Body $body
    if (!$response.result -or !$response.result._p2) { throw "LMS-Einstellung $name nicht lesbar." }
    return $response.result._p2
}
$cache=Read-LmsPreference 'cachedir'
$library=Read-LmsPreference 'librarycachedir'
$media=@(Read-LmsPreference 'mediadirs')
& "$PSScriptRoot\Install-DBRepair.ps1" -ServiceName $services[0].Name -CacheDir $cache -LibraryDir $library -MediaDirs $media -ReplaceExisting:$ReplaceExisting
if ($RestartLms) {
    . "$PSScriptRoot\DBRepair.Core.ps1"
    $queue=Assert-Child $cache (Join-Path $cache 'dbrepair')
    foreach($marker in @('working.json','scan.pending','scan.running')) {
        if(Test-Path -LiteralPath (Join-Path $queue $marker)){throw 'Wartung aktiv. Kein weiterer Neustart angefordert.'}
    }
    $requestPath=Assert-Child $queue (Join-Path $queue 'request.json')
    $stream=[IO.File]::Open($requestPath,'CreateNew','Write','None')
    try {
        $json=@{action='restart';id='';created=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()} | ConvertTo-Json
        $bytes=[Text.Encoding]::UTF8.GetBytes($json)
        $stream.Write($bytes,0,$bytes.Length)
    } finally { $stream.Dispose() }
    Write-Output 'Einmaliger LMS-Neustart angefordert; erfolgt innerhalb etwa einer Minute. Keine Datenbankloeschung.'
    return
}
Write-Output 'Helfer eingerichtet. LMS bei passender Gelegenheit neu starten und DB Repair aktivieren. Kein Reset wurde ausgefuehrt.'
