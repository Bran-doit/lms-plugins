# LMS Plugins

Plugins for Lyrion Music Server, maintained by Bran-doit.

## In LMS installieren

Unter **Einstellungen → Plugins → Zusätzliche Repositories** diese Adresse eintragen:

```text
https://github.com/Bran-doit/lms-plugins/releases/download/repository/repo.xml
```

Die Adresse wird mit der ersten erfolgreichen Veröffentlichung verfügbar.

### Lyric-Translator

Lokale Liedtextübersetzung in acht Sprachen. Benötigt **Windows x64**, **LMS 8.x/9.x** und das aktive Plugin **Music and Artist Information**. Details: [Plugin-Anleitung](Plugins/LyricTranslator/README.txt).

## Updates veröffentlichen

1. Plugin-Dateien unter `Plugins/<Name>/` bearbeiten und testen.
2. Die Version in `install.xml` erhöhen. Bereits veröffentlichte Versionen werden nicht überschrieben.
3. Änderungen nach `main` hochladen. Dieser Schritt gibt die neue Version zur Veröffentlichung frei.

GitHub Actions führt Tests aus, erstellt versionierte ZIP-Dateien, berechnet die LMS-SHA1-Prüfsummen und veröffentlicht Releases. Erst wenn alle ZIP-Dateien verfügbar sind, wird die gemeinsame `repo.xml` aktualisiert. Sie muss nicht von Hand bearbeitet werden. Unter **Actions → Publish LMS plugins → Run workflow** kann ein fehlgeschlagener Lauf erneut gestartet werden.

Lokal prüfen: `python -m unittest discover -s tests` und `python scripts/publish.py` (erstellt nur Dateien in `dist/`).

Weitere Plugins können später jeweils in einem eigenen Ordner ergänzt werden. Die gemeinsame LMS-Adresse bleibt gleich. Änderungen auf anderen Branches werden nicht veröffentlicht.

## Lizenz

Die Lizenz eines Plugins steht in dessen Ordner. Lyric-Translator verwendet die MIT-Lizenz; Hinweise zu Fremdkomponenten stehen in `THIRD-PARTY.txt`.
