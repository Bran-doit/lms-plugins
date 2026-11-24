Radio Stations 0.9.0

Radio > Radio Favoriten verwendet den nativen LMS-XMLBrowser mit den vom Skin
angebotenen Listen-/Coveransichten. Der Stift öffnet den nativen Favoriteneditor
mit Einzelbearbeitung, Drag-and-drop, Hinzufügen, Ausschneiden und Einfügen.
Die Radio-Liste ist flach. Ordner und Dateiimport/-export sind dort ausgeblendet.

Automatische Übernahme:
Neue erkannte Radiosender aus den allgemeinen LMS-Favoriten werden einmalig
kopiert (Standard) oder bei aktiviertem Verschieben nach geprüfter Speicherung
aus den allgemeinen Favoriten entfernt. Ohne aktivierte automatische Erkennung
findet keine Übernahme statt. Unklare Audio-Links und Podcasts bleiben erhalten.
Ein Wechsel zwischen Kopieren und Verschieben verarbeitet alte Sender nicht erneut.
Manuell zurück zu Favoriten geschobene Sender sind dauerhaft ausgeschlossen.
Auch ein gelöschter, schon automatisch übernommener Sender wird nicht wiederholt
importiert. Diese Zuordnung erfolgt anhand der exakten Stream-URL.

In den Einstellungen speichert Hinzufügen eine manuelle URL sofort; ein optionaler
Name kann angegeben werden. Alte vorgemerkte manuelle Einträge werden beim Öffnen
in den dauerhaften Speicher übernommen. Es gibt keinen Übernehmen- oder A-Z-Button.
Die Reihenfolge wird über Pfeile bzw. im nativen Editor per Drag-and-drop geändert.
Alle übrigen Radio-Browser-Listen bleiben alphabetisch.

Gespeichert wird in radiostations-favorites.json im LMS-Einstellungsverzeichnis,
mit Sicherungen vor Änderungen. Die Musikdatenbank wird nicht verändert.
Editor und Einstellungen verwenden denselben Speicher; veraltete Editorsitzungen
können gleichzeitige Änderungen nicht überschreiben. Zurückverschieben erstellt
keine zusätzlichen Duplikate bei zuvor kopierten Sendern.

Erkennung: bekannte Radio-URLs, TuneIn-Kennungen, Radio-Browser-Treffer oder
geeignete ICY-Metadaten. Öffentliche Stream-URLs können an Radio Browser gesendet
werden; lokale und erkennbare Zugangsdaten-URLs werden dort nicht angefragt.
Keine Audiodownloads. Unklare und nicht erreichbare Links werden nicht übernommen.

Cover: Vorhandene Titelbilder aus LMS/Metadaten haben Vorrang. Gespeicherte
Senderlogos werden über den nativen LMS-Bildcache als Ersatz bereitgestellt,
auch für aufgelöste Streams. Keine zusätzliche externe Titelcover-Suche.

Navigation nach Ländern und Regionen erfolgt mit den Radio-Browser-Daten,
auch für das konfigurierte lokale Länderkürzel. Alle Sender bleibt verfügbar.

Eigenständiger Fork von Radio Browser 0.3.10 von hjelev:
https://github.com/hjelev/lyr-radio-browser
Seit 0.8.0 GPL-2.0-Editorcode aus Lyrion Music Server; siehe LICENSE.
Ursprüngliche MIT-Copyright-Hinweise: LICENSE-MIT.txt.
Installation: RadioStations in das zusätzliche LMS-Plugin-Verzeichnis kopieren,
LMS neu starten. Radio Browser kann parallel installiert bleiben.
