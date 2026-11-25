# DB Repair

[Deutsche Anleitung](README.md)

Database diagnostics, backups, rebuilding and service restart for Lyrion Music Server running as a Windows service. DB Repair does not repair corrupt database pages in place: a rebuild backs up the database and scans the music files again.

## Requirements and installation

Windows PowerShell 5.1 or later and LMS 9.0.3–9.1.x according to the manifest; live operation has been tested with LMS 9.0.3. Add this URL under **Settings → Plugins → Additional repositories**, install DB Repair and restart LMS as requested:

```text
https://github.com/Bran-doit/lms-plugins/releases/download/repository/repo.xml
```

Maintenance actions require a separate privileged Windows helper. The plugin manager cannot install it automatically. Open an administrative PowerShell **on the LMS server**, change to the installed DBRepair plugin directory and run:

```powershell
.\helper\Install-On-Server.ps1
```

Automatic detection requires exactly one LMS service and access to `http://127.0.0.1:9000` without authentication. Otherwise specify the actual settings explicitly:

```powershell
.\helper\Install-DBRepair.ps1 -ServiceName 'YOUR-LMS-SERVICE' -CacheDir 'C:\LMS-Cache' -LibraryDir 'C:\LMS-Cache' -MediaDirs @('D:\Music')
```

Replace the example values. Database and backup directories must be local, on the same drive, and must not contain symbolic links or junctions. SYSTEM must be able to read network music paths; use UNC paths rather than mapped drives. Installation does not reset the database. The helper runs as SYSTEM through the **DB Repair Worker** scheduled task, approximately once per minute. Its code/configuration live under `Program Files\DB Repair`; backups default to `DBRepair-Backups` at the database drive root.

## Usage and language

Open **Settings → Advanced → DB Repair**. Starting with 0.8.0, German is used when the LMS system language is German; English is used for every other language. Reload the page after changing LMS language. No browser-language or separate plugin-language setting is required.

- **Restart LMS** stops and starts the service once.
- **Back up database** stops LMS, copies the database and existing SQLite sidecar files, then restarts with the original database. No rebuild is requested.
- **Back up and rebuild database** saves and removes the old database, then requests a full scan. Database-internal extra information may be lost. Music files, settings and `persist.db` are preserved.
- **Check database** runs a read-only quick check, full integrity check or comparison against a saved backup. The time limit is ten minutes. A running scan must finish first.
- **Virtual library tracing** optionally records server/scanner operations. Overlapping events do not prove a SQLite write conflict. Logs are bounded and may contain gaps.
- **Copy check report** exports the full original JSON. Reports may be permanently protected; the first healthy and first failed reports are protected automatically, alongside the latest 20 unprotected reports.

Maintenance actions show confirmation dialogs. Restart, backup and rebuild interrupt playback and the web interface. Deleting a selected backup is permanent.

## Diagnostic limits

An integrity result of `ok` does not prove that every music file or library assignment is correct. Current database, backup and content comparison have separate findings. New backup evidence includes file sizes, SHA-256 and observed service/scanner state. Missing historical evidence does not automatically invalidate an older backup.

The UI translates its own labels, confirmations, status messages and diagnostic explanations. Original JSON evidence, SQL output, paths and native Windows/SQLite errors remain unchanged; historical reports can therefore contain German text. Administrative helper console output also remains in its original language. Reports may include private local paths and system context: review them before sharing publicly.

## Updates, validation and license

Update the plugin through LMS and restart to load it. The 0.8.0 language update keeps helper protocol 0.7.0 and needs no helper update. When a future helper update is needed, run `Install-On-Server.ps1 -ReplaceExisting`; optional `-RestartLms` requests a service restart afterwards.

Automated tests cover both rendered languages, fallback from other LMS languages, confirmations, read-only checks, comparisons, evidence and tracing. Windows helper tests mock service access and use temporary files. Publishing does not install or restart a live server.

[MIT license](LICENSE) · [Changelog](CHANGELOG.md) · [SQLite integrity checks](https://www.sqlite.org/pragma.html#pragma_integrity_check) · [Lyrion source](https://github.com/LMS-Community/slimserver)
