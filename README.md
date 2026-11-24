# LMS Plugins

Plugins for Lyrion Music Server, maintained by Bran-doit.

## In LMS installieren

Unter **Einstellungen → Plugins → Zusätzliche Repositories** diese Adresse eintragen:

```text
https://github.com/Bran-doit/lms-plugins/releases/download/repository/repo.xml
```

Radio Stations oder Lyric-Translator auswählen und den Installationshinweisen von LMS folgen.

### Radio Stations

Radiosender aus Radio Browser nach Land und Region durchsuchen. Eigene Radio-Favoriten mit nativer Bearbeitung, manuellen Stream-Links, Senderlogos und optionaler automatischer Übernahme aus LMS-Favoriten. Für **LMS 8.x/9.x**. [Anleitung](Plugins/RadioStations/README.md) · [Änderungsverlauf](Plugins/RadioStations/CHANGELOG.md).

### Lyric-Translator

Lokale Liedtextübersetzung in acht Sprachen mit automatischer Spracherkennung, Übersicht eingerichteter Sprachen und optionalem automatischem Modelldownload. Clients können auch Original-Lyrics abrufen. Benötigt **Windows x64**, **LMS 8.x/9.x** und das aktive Plugin **Music and Artist Information**. [Anleitung](Plugins/LyricTranslator/README.md) · [Client-API](Plugins/LyricTranslator/CLIENT-API.md) · [Änderungsverlauf](Plugins/LyricTranslator/CHANGELOG.md).

## Updates veröffentlichen

1. Plugin-Dateien unter `Plugins/<Name>/` bearbeiten und testen.
2. Die Version in `install.xml` erhöhen. Bereits veröffentlichte Versionen werden nicht überschrieben.
3. Änderungen nach `main` hochladen. Dieser Schritt gibt die neue Version zur Veröffentlichung frei.

GitHub Actions führt Tests aus, erstellt versionierte ZIP-Dateien, berechnet die LMS-SHA1-Prüfsummen und veröffentlicht Releases. Erst wenn alle ZIP-Dateien verfügbar sind, wird die gemeinsame `repo.xml` aktualisiert. Sie muss nicht von Hand bearbeitet werden. Unter **Actions → Publish LMS plugins → Run workflow** kann ein fehlgeschlagener Lauf erneut gestartet werden.

Lokal prüfen: `python -m unittest discover -s tests` und `python scripts/publish.py` (erstellt nur Dateien in `dist/`).

Weitere Plugins können später jeweils in einem eigenen Ordner ergänzt werden. Die gemeinsame LMS-Adresse bleibt gleich. Änderungen auf anderen Branches werden nicht veröffentlicht.

## Lizenz

Die Lizenz eines Plugins steht in dessen Ordner. Lyric-Translator verwendet die MIT-Lizenz; Hinweise zu Fremdkomponenten stehen in `THIRD-PARTY.txt`.

Radio Stations wird als kombinierte Distribution unter GPL v2 bereitgestellt; ursprüngliche MIT- und LMS-Lizenzhinweise stehen im Plugin-Ordner.
