DB Repair 0.8.0 - Windows-Dienst-Version

Zweck
Die echte library.db wird bei gestopptem LMS aus dem Cache in eine Sicherung
verschoben. Nach dem Neustart wird aus den Musikdateien neu eingelesen.
Kein wipecache und keine Reparatur innerhalb der beschaedigten Datenbank.
Die Sicherungen koennen ueber dieselbe Einstellungsseite endgueltig geloescht
werden. Musikdateien, Einstellungen und persist.db werden nicht geloescht.
Ein Neuaufbau kann datenbankinterne Zusatzdaten verlieren.

Installation AUF dem LMS-Server (Administrator)
1. Den Ordner DBRepair nach server\Plugins\DBRepair kopieren.
   Fuer die bekannte Installation auf dem LMS-Server kann danach in administrativer
   PowerShell direkt helper\Install-On-Server.ps1 ausgefuehrt werden. Dieses
   Skript ermittelt Dienst, Cache, Bibliotheksordner und Musikordner automatisch
   ueber die lokale LMS-Schnittstelle (Port 9000, ohne Anmeldung). Es installiert
   nur den Helfer. Bei LMS-Anmeldung stattdessen die folgenden Schritte nutzen.
2. Tatsaechlichen Cachepfad in LMS unter Einstellungen / Informationen ablesen.
   Er muss library.db enthalten. Dienstnamen mit Get-Service ermitteln.
3. In einer administrativen Windows PowerShell (5.1 oder neuer):

   & 'C:\Pfad\server\Plugins\DBRepair\helper\Install-DBRepair.ps1' `
       -ServiceName 'TATSAECHLICHER_DIENSTNAME' `
       -CacheDir 'C:\TATSAECHLICHER_CACHEPFAD' `
       -MediaDirs @('D:\Musik','\\NAS\Audio')

   Beispielpfade ersetzen. ALLE tatsaechlichen LMS-Musikordner angeben.
   Standard: Helfer in Program Files\DB Repair; Sicherungen im Ordner
   DBRepair-Backups im Stamm des Cache-Laufwerks. Optional -BackupDir angeben.
   Cache und Sicherung muessen auf demselben lokalen Laufwerk liegen.
   Bei abweichendem librarycachedir zusaetzlich -LibraryDir angeben; Sicherung
   und Bibliotheksordner muessen dann auf demselben Laufwerk liegen.
   Keine Junctions/Symlinks in Cache-, Helfer- oder Sicherungspfaden.
4. LMS kontrolliert neu starten, DB Repair aktivieren und Einstellungen oeffnen.
   'Windows-Helfer erreichbar' muss erscheinen. Die Installation startet
   KEINEN Reset. Bestehende Wiedergabe vor dem Neustart beruecksichtigen.

Bedienung
Unter Einstellungen / Erweitert / DB Repair gibt es drei direkte Buttons:
- LMS neu starten: Dienst einmal stoppen/starten; Datenbank bleibt erhalten.
- Datenbank sichern und neu aufbauen: bisheriger vollstaendiger Reset.
- Ausgewaehlte Sicherung loeschen: endgueltige Loeschung nur dieser Sicherung.
Jeder Button zeigt einen Bestaetigungsdialog. OK fuehrt den Auftrag direkt aus,
Abbrechen tut nichts. Keine Worteingabe und kein zusaetzliches Speichern.
Waehrend eines Auftrags sind weitere Aktionen gesperrt. Die Seite prueft bis
zu zehn Minuten die Erreichbarkeit und laedt nach Abschluss automatisch neu.
Der Windows-Helfer bearbeitet Auftraege innerhalb etwa einer Minute.
Bei aktivem Scan wird ein Neustart verweigert; zuerst Scan abschliessen lassen.

Update von 0.1.0 auf 0.2.0
Plugin-Dateien ersetzen. Auf dem LMS-Server einmal administrativ ausfuehren:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Pfad\server\Plugins\DBRepair\helper\Install-On-Server.ps1" -ReplaceExisting -RestartLms
Damit wird der geschuetzte Windows-Helfer aktualisiert und ein einmaliger
Neustart zur Aktivierung angefordert. Keine Datenbankloeschung. Ohne diesen
Helfer-Update bleibt der neue Neustart-Button gesperrt.
Betrieb und Grenzen
- Task 'DB Repair Worker' laeuft als SYSTEM jede Minute, ohne sichtbares Fenster.
- SYSTEM muss Musikordner lesen koennen. UNC statt Benutzer-Laufwerksmapping.
  Der LMS-Dienst braucht ebenfalls Zugriff. Nicht erreichbare/leere Quellen
  blockieren den Reset. Zugriffsrechte koennen nach der Installation variieren.
- Bestehende Scanner werden nicht gewaltsam beendet. Reset verweigert, solange
  ein Scanner lebt; nach dessen Ende erneut versuchen.
- Verschoben werden ausschliesslich library.db sowie vorhandene -wal, -shm,
  -journal Begleitdateien. Andere Datenbanken/Caches bleiben erhalten.
- Config und Helfer sind nur fuer Administratoren/SYSTEM beschreibbar. Die
  Weboberflaeche nimmt keine Dateipfade oder Shell-Kommandos entgegen.
- Sicherung ist ein Verschieben auf demselben Laufwerk, kein zweites Kopieren.
  Scheitert ein Teil, werden bereits verschobene Dateien zurueckverschoben.
- Neustart wird auch bei Fehlern versucht. Falls er scheitert: Windows-Dienst
  vor Ort pruefen. Ein beschaedigtes System/fehlender Speicher wird nicht geheilt.
- Bei Stromausfall/Abbruch wird ein working.json nicht automatisch wiederholt.
  Administrator prueft Status, aktive library.db und Sicherungen; erst danach
  working.json entfernen. Keine automatischen wiederholten Reset-Schleifen.
- scan.pending/scan.running sind absichtliche Sperren bis Scanende. Bei haengendem
  Scan oder Plugin-Ausfall vor Ort Scannerprotokoll pruefen. Nicht blind entfernen.
- Falls LMS gar nicht startet, ist die Pluginseite nicht erreichbar. Dieses Paket
  bietet keine unabhaengige Weboberflaeche fuer diesen Fall.

Manuelle Wiederherstellung
LMS und Scanner stoppen. Aktuelle library.db und ihre Begleitdateien separat
sichern. Dateien aus EINER DBRepair-Sicherung gemeinsam in den Cache zurueck-
verschieben. scan.pending/scan.running nach Pruefung entfernen. Dienst starten.
Eine alte beschaedigte Datenbank kann natuerlich wieder denselben Fehler zeigen.

Deinstallation
Task 'DB Repair Worker' deaktivieren/entfernen, wenn kein Auftrag laeuft.
Plugin deaktivieren, LMS neu starten. Helferordner und Warteschlange erst nach
Pruefung entfernen. Sicherungen bleiben erhalten und separat loeschbar.

Validierung
Lokale isolierte Tests pruefen echten Dateiverschub, Begleitdateien, Ruecknahme
bei Fehlern, Sicherungsloeschung und Pfadbegrenzung. Keine produktive Datenbank
wird dabei angefasst. Live-Abnahme auf dem LMS-Server ist separat erforderlich.


Diagnose ab Version 0.3.0
Schnellpruefung: PRAGMA quick_check(2147483647).
Vollstaendige Pruefung: PRAGMA integrity_check(2147483647).
Beide laufen manuell in einem separaten unsichtbaren Perl-Prozess mit der
vorhandenen LMS-Laufzeit, nicht im Webserver-Eventloop. Kein Helferupdate noetig.
LMS einmal ueber den bestehenden Neustart-Button neu starten zum Aktivieren.

Die SQLite-Verbindung verwendet SQLITE_OPEN_READONLY und query_only, eine
Lesetransaktion fuer den konsistenten Datenstand und ein Zeitlimit von zehn
Minuten (zusaetzlicher Prozessabbruch nach 630 Sekunden). Ein langer Leser
kann SQLite-Schreibzugriffe/Checkpoints beeinflussen und WAL-Wachstum verursachen.
Vorhandene Scans und DB-Repair-Auftraege blockieren den Start. Andere Plugins
oder ein spaeter gestarteter LMS-Scan werden nicht global gesperrt.

Ergebnis: ok, SQLite-Befunde oder Ausfuehrungsfehler (z.B. gesperrt, abgebrochen,
fehlende Datenbank). Ausfuehrungsfehler beweisen allein keine Korruption.
Leere Dateien und Datenbanken ohne tracks-Tabelle gelten nicht als gesund.
Pruefungen betreffen library.db, nicht persist.db oder andere Cachedateien.
Keine Reparatur, keine Musikdateipruefung, keine vollstaendige Fremdschluessel-
oder FTS-Semantikpruefung. quick_check prueft nicht alle Index-/UNIQUE-Details.

Letzte 20 Berichte als check-*.json im Cache/dbrepair, mit UTC-Zeitstempel,
Laufzeit, manueller Kennzeichnung und vollstaendiger zurueckgegebener SQLite-Ausgabe.
Vorher-/Nachher-Kennzeichnungen loesen keine automatischen Scans oder Checks aus.
Grundlage: https://sqlite.org/pragma.html#pragma_integrity_check

Erweiterte Protokollierung 0.4.0
Jeder neue Bericht hat eine Pruef-ID, UTC-Start/Ende, Epoch-Zeiten und Laufzeit,
Original-Datenbankpfad, exakten PRAGMA-Befehl sowie ungekürzte Ausgabe.
Der SQLite-Befundgrenzwert ist 2147483647; das Zeitlimit bleibt bestehen.
Abbruch/Fehler markiert output_complete=false; erhaltene Teilbefunde bleiben stehen.

server_start und server_finish enthalten Zeit, LMS-Version, DB-Repair-Version,
aktiv geladene Plugins mit bekannten Versionen, LMS-PID, Scanstatus und die PID
des von LMS verwalteten Scannerprozesses (falls vorhanden). Externe Scanner
sind damit nicht vollstaendig erfasst. Fehlende Daten tragen eine Fehlerangabe
oder 'unknown'; es werden keine Versionen/PIDs geraten.

LMS-Verbindung: SQLite-Version, journal_mode, synchronous, locking_mode,
busy_timeout werden lesend erfasst. Diagnoseverbindung: dieselben Werte plus
query_only, DBI-/DBD::SQLite-/Perl-Version und Diagnose-PID. Diese Werte sind
getrennt, da PRAGMAs verbindungsspezifisch sein koennen. Keine Einstellung der
LMS-Verbindung wird fuer die Protokollierung geaendert.

Fehler enthalten DBI/SQLite-Code, primaeren SQLite-Code, SQLSTATE, vollstaendige
Meldung und Perl-Aufrufkette. Kategorie unterscheidet corruption, locked,
interrupted und execution_error; Prozessabbrueche sind process_error und
besitzen nicht notwendigerweise einen SQLite-Fehlercode.

Die Auswahl vor/nach Scan bzw. vor/nach Bibliotheksaktualisierung ist eine
manuelle Kennzeichnung. trigger=manual bleibt explizit; keine automatische
Ereigniszuordnung wird behauptet. Alte Berichte werden nicht nachtraeglich
mit erfundenen Metadaten vervollstaendigt. JSON-Protokoll auf der Seite aufklappen.

Datenbankvergleich 0.5.0
Unter Datenbank pruefen die Pruefart 'Aktuelle Datenbank mit Backup vergleichen'
waehlen; daneben eine vorhandene DB-Repair-Sicherung auswaehlen. Pruefung starten
und Dialog bestaetigen. Kein Helferupdate erforderlich, nur LMS-Neustart zum Laden.

Beide Datenbanken werden read-only mit integrity_check geprueft. Pro Datenbank
liegen Integritaetspruefung und Datenaufnahme in EINER Lesetransaktion. Die beiden
Transaktionen laufen nacheinander, nicht als gemeinsamer historischer Zeitpunkt.
Gemeinsames Zeitlimit zehn Minuten; Fehler erhalten auch den Befund der anderen DB.
Schema: Tabellen, Spalten, Indizes, Original-SQL und explizite Objektunterschiede.
Bestand: tracks, albums und library_track; fehlende Tabellen sind unbekannt statt 0.
Titelvergleich per exakter URL: hinzugekommen/entfernt, geaenderte Bibliotheks-
kennungen. Titel-IDs werden nur innerhalb einer DB zum Aufloesen verwendet.
Mehrdeutige URLs, nicht zuordenbare Titel und verwaiste Zuordnungen sind markiert.
Bibliothekskennungen koennen beim Neuaufbau wechseln; ihr Unterschied allein
beweist keinen inhaltlichen Fehler. Allgemeine Tag-/Metadatenvergleiche sind
in dieser Version nicht enthalten. OK bezeichnet Integritaet, nicht Identitaet.

Der Sicherungspfad wird aus der bestehenden geschuetzten Helferkonfiguration
unter Program Files\DB Repair\config.json gelesen und die Auswahl gegen den
Sicherungskatalog geprueft. Keine freien Dateipfade aus Webformularen. LMS muss
Konfiguration und Sicherung lesen duerfen. Bei abweichendem Helferinstallations-
ordner oder fehlendem Zugriff wird mit klarer Fehlermeldung abgebrochen.

Jeder Bericht hat 'Pruefprotokoll kopieren'. Es wird das gesamte JSON kopiert,
inklusive beider Pruefungen und aller Unterschiede. HTTPS verwendet Clipboard API;
HTTP nutzt den Browser-Kopierbefehl. Falls blockiert, bleibt ein markiertes Textfeld
zum manuellen Kopieren. Browser-Sicherheitsregeln werden nicht umgangen.

Diagnosebelege und Ablaufdiagnose 0.6.0
Die Oberflaeche zeigt aktuelle Datenbank, Sicherung und Inhaltsvergleich getrennt.
Schadensgruppen und nachgewiesene Index-/Tabellenzuordnungen stehen im JSON.
Seiten werden nicht anhand von Vermutungen Tabellen zugeordnet. synchronous=OFF
wird als geringere Ausfallsicherheit erklaert, nicht als Plugin-Konflikt bewertet.
Die Einstellung wird nicht veraendert.

Der erste gesunde und der erste fehlerhafte Bericht werden automatisch geschuetzt.
Weitere Berichte lassen sich mit 'Bericht dauerhaft aufbewahren' schuetzen.
Geschuetzte Berichte samt vorhandenen Kontext- und Ablaufdateien bleiben neben den
letzten 20 ungeschuetzten Berichten erhalten. Fehlende historische Daten werden
nicht nachtraeglich erfunden. Alle gespeicherten Details werden mitkopiert.

Die zuschaltbare Ablaufdiagnose protokolliert registerLibrary, unregisterLibrary,
rebuild, Auswahl-Callbacks, SQL-Phasen und Benachrichtigungen im Server und Scanner.
Ein neu gestarteter Scanner importiert DB Repair ueber importmodule. Bereits vor
der Instrumentierung gelaufene Operationen koennen nicht aufgezeichnet werden.
Prozess, Mikrosekunden-Zeitstempel, Aufrufkette, Operations-ID, Eltern-ID und Tiefe
werden erfasst. Verbindungskennungen stammen aus tatsaechlich beobachteten SQL-
Handles; ein Root-Beginn ohne SQL hat zunaechst keine Verbindungskennung. Keine
zusaetzliche Datenbankverbindung wird allein fuer diese Kennung geoeffnet.
SQL-Texte sind auf 4000 Zeichen begrenzt. Lesende Zugriffe ausserhalb beobachteter
Operationen werden nicht erfasst. Kein vollstaendiges SQL-Audit wird behauptet.

Prozessdateien rotieren bei etwa 2 MiB, insgesamt werden hoechstens 24 Dateien
behalten (etwa 48 MiB zuzueglich des letzten Ereignisses). Berichtsschnappschuesse
sind davon unabhaengig. Geschuetzte Belege koennen entsprechend Speicher belegen.
Die gemeinsame Zeitleiste markiert Verschachtelung, zeitliche Ueberschneidung und
fehlende Enden. Ueberschneidung ist kein bewiesener SQLite-Schreibkonflikt.
Pruefberichte speichern das Pruefintervall plus bis zu fuenf Minuten Vorlauf aus
noch vorhandenen Protokollen. 'Ablaufprotokoll sichern' erfasst alle derzeit
vorhandenen Ereignisse. Fehlende Enden bleiben mehrdeutig: aktiv, Abbruch oder
Rotation. Pruefungen werden nicht aus aktiven beobachteten Callbacks gestartet.
Beobachtung fuegt keine Commits, Datenbanksperren oder Reparaturen hinzu; bestehende
Callbacks und ihre Rueckgabewerte bleiben erhalten. Dateizugriffe kosten Laufzeit.

Neue Sicherungsnachweise erfordern Windows-Helfer 0.6.0. Der Helfer dokumentiert
Dienstzustand und Scannerabwesenheit vor dem Verschieben, die Sicherungsmethode,
Dateigroessen und SHA-256 fuer library.db samt vorhandenen WAL/SHM/Journaldateien.
Kein zusaetzlicher Checkpoint: Sidecars werden unveraendert mitgenommen.
LMS-/Plugin-/SQLite-Kontext stammt aus dem Auftrag vor dem Dienststopp und ist
getrennt vom Zustand beim Verschieben und vom heutigen Pruefkontext.
Das Verfahren belegt keine logische Fehlerfreiheit. Alten Sicherungen ohne diese
Metadaten wird 'Sicherungskonsistenz nicht belegt' zugeordnet, nicht 'ungueltig'.

Aktivierung auf dem LMS-Server: Plugin-Dateien laden nach LMS-Neustart. Fuer erweiterte
Sicherungsnachweise einmal administrativ den mitgelieferten Helfer aktualisieren:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Pfad\server\Plugins\DBRepair\helper\Install-On-Server.ps1" -ReplaceExisting -RestartLms
Dieser Aufruf aktualisiert den Helfer und startet LMS neu; er setzt keine DB zurueck.
Nur fuer Ablaufdiagnose und Oberflaeche reicht der bestehende Neustart-Button.
UTF-8: dynamische Perl-Texte sind als Unicode deklariert; HTML verwendet Entitaeten.
LMS muss neu starten, damit alte gecachte Vorlagen und Module ersetzt werden.

Datenbankoperationen 0.7.0
Die bisherige Reset-Kachel heisst Datenbankoperationen. Auswahl:
- Datenbank sichern und neu aufbauen: bisheriges Verhalten.
- Datenbank sichern: neue Kopie von library.db und vorhandenen SQLite-Sidecars.
Fuer beide Operationen wird LMS gestoppt und danach gestartet; Wiedergabe und UI
werden unterbrochen. Beim Kopieren bleibt die aktive Datenbank erhalten und es
wird kein Scan-Marker angelegt. Sicherung im Katalog und Vergleich auswaehlbar.
Die Kopie hat eine eigene ID, Dateigroessen, SHA256 und Entstehungskontext.
Ein gesperrtes Sidecar bricht die Kopie ab; unvollstaendige Kopie wird entfernt.
Datenbank sichern benoetigt Windows-Helfer 0.7.0. Alte Helfer werden abgewiesen.
Einmal auf dem LMS-Server administrativ aktualisieren und Plugin laden:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Pfad\server\Plugins\DBRepair\helper\Install-On-Server.ps1" -ReplaceExisting -RestartLms

Sprache ab 0.8.0: LMS-Systemsprache Deutsch -> Deutsch, sonst Englisch.
Oberflaeche und Dialoge wechseln automatisch; JSON-Belege bleiben original.
Kein Helferupdate erforderlich. Englische Anleitung: README.en.md.
