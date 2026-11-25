# DB Repair

DB Repair ergänzt die LMS-Verwaltung um Datenbankdiagnosen, Sicherungen, einen vollständigen Neuaufbau und einen Neustart des Windows-Dienstes. Eine beschädigte Datenbank wird **nicht direkt repariert**: Der Neuaufbau sichert sie und liest die Musikdateien neu ein.

## Voraussetzungen

- Windows mit LMS als Dienst; Windows PowerShell 5.1 oder neuer.
- LMS 9.0.3 bis 9.1.x laut Manifest; praktisch erprobt mit 9.0.3. Andere Versionen sind nicht vollständig live geprüft.
- Für Sicherung, Neuaufbau, Löschen und Neustart: einmalig administrativ installierter Windows-Helfer. Der LMS-Pluginmanager installiert diesen privilegierten Helfer nicht automatisch.
- Lokale Datenbank- und Sicherungspfade auf demselben Laufwerk, ohne Junctions/Symlinks. Musikfreigaben müssen für das SYSTEM-Konto erreichbar sein; keine gemappten Laufwerksbuchstaben verwenden.

## Installation

In LMS unter **Einstellungen → Plugins → Zusätzliche Repositories** eintragen:

```text
https://github.com/Bran-doit/lms-plugins/releases/download/repository/repo.xml
```

DB Repair installieren und LMS nach Aufforderung neu starten. Auf dem LMS-Rechner anschließend eine administrative PowerShell öffnen und im installierten Pluginordner ausführen:

```powershell
.\helper\Install-On-Server.ps1
```

Das Skript erkennt genau einen LMS-Dienst und liest die lokalen Einstellungen über `http://127.0.0.1:9000` ohne Anmeldung. Bei anderem Port, aktivierter Anmeldung oder mehreren Diensten stattdessen explizite Werte verwenden:

```powershell
.\helper\Install-DBRepair.ps1 -ServiceName 'LMS-DIENSTNAME' -CacheDir 'C:\LMS-Cache' -LibraryDir 'C:\LMS-Cache' -MediaDirs @('D:\Musik')
```

Beispielwerte ersetzen. Die Installation führt keinen Datenbankreset aus. Der Helfer wird unter `Program Files\DB Repair` installiert und über die Aufgabe **DB Repair Worker** als SYSTEM etwa einmal pro Minute ausgeführt. Sicherungen liegen standardmäßig im Ordner `DBRepair-Backups` am Stamm des Datenbanklaufwerks. Weitere Details: [technische Anleitung](README.txt).

## Bedienung

Unter **Einstellungen → Erweitert → DB Repair**:

- **LMS neu starten**: einmaliger Dienstneustart.
- **Datenbank sichern**: bei gestopptem Dienst eine Kopie einschließlich vorhandener WAL-/Journaldateien erzeugen; anschließend mit der bestehenden Datenbank weiterarbeiten.
- **Datenbank sichern und neu aufbauen**: alte Datenbank sichern und aus dem aktiven Ordner entfernen; danach Scan anfordern. Datenbankinterne Zusatzdaten können verloren gehen. Musikdateien, Einstellungen und `persist.db` bleiben erhalten.
- **Datenbank prüfen**: `quick_check`, `integrity_check` oder Vergleich mit einer vorhandenen Sicherung. Vergleich umfasst Integrität, Schema, Bestände und Titel-/Bibliothekszuordnung über URLs.
- **Ablaufdiagnose**: optional virtuelle Bibliotheksoperationen im Server und Scanner beobachten. Zeitliche Überschneidung allein beweist keinen Schreibkonflikt.
- Prüfprotokolle kopieren und dauerhaft schützen. Der erste gesunde und erste fehlerhafte Bericht werden automatisch geschützt; zusätzlich bleiben die letzten 20 ungeschützten Berichte erhalten.

Die Wartungsaktionen verlangen einen Bestätigungsdialog. Sicherung, Neuaufbau und Neustart unterbrechen Wiedergabe und Oberfläche. Während eines Scans sind sie gesperrt. Das Löschen einer ausgewählten Sicherung ist endgültig.

## Grenzen und Diagnosebelege

Integritätsprüfungen sind lesend, laufen separat und haben ein Zeitlimit von zehn Minuten. Ein `ok` bestätigt keine vollständige Musiksammlung und keine fachlich richtigen Freigaben. Aktuelle Datenbank, Sicherung und Inhaltsvergleich haben getrennte Befunde. Neue Sicherungen dokumentieren Dateigrößen, SHA-256, Entstehungszeit und beobachteten Dienst-/Scannerzustand. Fehlende historische Nachweise machen alte Sicherungen nicht automatisch ungültig.

Die Ablaufdiagnose ist standardmäßig aus; begrenzte Prozessprotokolle können Lücken enthalten. Sie fügt keine Reparaturen, Commits oder Datenbanksperren hinzu. `synchronous=OFF` wird erläutert, nicht automatisch geändert. Diagnoseberichte enthalten lokale Pfade und Systemkontext; vor öffentlichem Teilen prüfen.

## Updates und Prüfung

LMS aktualisiert das Plugin. Den getrennt installierten Helfer bei erforderlichen Änderungen administrativ mit `Install-On-Server.ps1 -ReplaceExisting` aktualisieren. Optional fordert `-RestartLms` anschließend einen Dienstneustart an. Plugin 0.7.1 verwendet weiterhin das Helferprotokoll 0.7.0.

Automatisierte Tests prüfen SQLite-Befunde, Vergleiche, Belege und Ablaufdiagnose; Windows-Tests simulieren Dienstzugriffe und prüfen Sicherung/Fehlerfälle mit temporären Dateien. Eine Veröffentlichung führt keine Wartungsaktion auf einem produktiven Server aus.

## Lizenz und Referenzen

[MIT-Lizenz](LICENSE). Laufzeitabhängigkeiten aus LMS, Perl und Windows werden nicht mitgeliefert und behalten ihre jeweiligen Lizenzen.

- [Änderungsverlauf](CHANGELOG.md)
- [SQLite PRAGMA-Dokumentation](https://www.sqlite.org/pragma.html#pragma_integrity_check)
- [Lyrion Music Server](https://github.com/LMS-Community/slimserver)
