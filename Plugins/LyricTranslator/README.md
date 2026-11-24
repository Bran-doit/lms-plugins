# Lyric-Translator

Liedtexte direkt im Lyrion Music Server lokal übersetzen — ohne Übersetzungs-API oder laufende Übersetzungsgebühren.

[Alle Plugins](../../README.md) · [Änderungsverlauf](CHANGELOG.md) · [Client-API](CLIENT-API.md) · [Ausführliche Anleitung / English](README.txt)

## Funktionen

- Übersetzung zwischen Deutsch, Englisch, Französisch, Italienisch, Niederländisch, Portugiesisch, Russisch und Spanisch.
- Automatische Erkennung der Ausgangssprache oder manuelle Auswahl.
- Originaltext auf Wunsch zusätzlich anzeigen.
- LRC-Zeitmarken, Zeilen und Leerzeilen erhalten.
- Fehlende unterstützte Sprachmodelle bei Bedarf automatisch im Hintergrund herunterladen; in den Einstellungen abschaltbar.
- Original-Liedtexte können von Clients auch ohne Übersetzung abgerufen werden.

## Voraussetzungen

**Windows x64**, **LMS 8.x oder 9.x** und das aktivierte Plugin **Music and Artist Information**. Eine GPU oder eine systemweite Python-Installation ist nicht erforderlich.

Für Einrichtung und Modelldownloads wird eine Internetverbindung benötigt. Auch der Abruf der Originaltexte durch Music and Artist Information kann auf Onlinequellen zugreifen. Übersetzung und Spracherkennung selbst laufen lokal.

## Installation über LMS

1. Unter **Einstellungen → Plugins → Zusätzliche Repositories** diese Adresse eintragen:

   ```text
   https://github.com/Bran-doit/lms-plugins/releases/download/repository/repo.xml
   ```

2. Einstellungen übernehmen, **Lyric-Translator** auswählen und den Installations- und Neustarthinweisen von LMS folgen.
3. Unter **Einstellungen → Erweitert → Lyric-Translator** die gewünschten Sprachen wählen.
4. **„Ausgewählte Sprachen einrichten“** anklicken. Die Einrichtung läuft im Hintergrund; die Einstellungsseite erneut öffnen, um den Fortschritt zu sehen.

Die erstmalige Einrichtung für Englisch–Deutsch einschließlich Spracherkennung benötigt etwa 132 MB. Andere Sprachpaare können abweichen. Vorhandene manuelle Installationen vor einer Umstellung auf die LMS-Pluginverwaltung prüfen, um doppelte Plugin-Kopien zu vermeiden.

## Bedienung und Einstellungen

Öffne die Titelinformationen und wähle **„Liedtext übersetzen: …“**. Die Ausgangssprache kann automatisch erkannt oder fest vorgegeben werden; die Zielsprache ist unabhängig von der LMS-Oberflächensprache.

**„Einstellungen speichern“** speichert die Auswahl. **„Ausgewählte Sprachen einrichten“** lädt zusätzlich die benötigten Modelle. Fehlende unterstützte Modelle werden standardmäßig auch bei einer Übersetzungsanfrage im Hintergrund ergänzt. Nach Abschluss die Übersetzung erneut abrufen. Diese Automatik lässt sich abschalten.

Die Oberfläche ist bei deutscher LMS-Sprache auf Deutsch, sonst auf Englisch. Die Einstellungen zeigen verfügbare Ausgangssprachen für die gewählte Zielsprache.

## Grenzen und Fehlerbehebung

- Kurze, unsichere oder gemischtsprachige Texte können eine manuelle Sprachauswahl erfordern.
- Bereits in der Zielsprache vorliegende Texte bleiben unverändert.
- Sprachpaare ohne direktes Modell werden über Englisch übersetzt; dabei kann Qualität verloren gehen.
- Zeilenweise Übersetzung erhält Zeitmarken, kann aber sprachlichen Kontext verlieren.
- Bei fehlenden Modellen den Einrichtungsstatus prüfen und die Anfrage später wiederholen.
- Die erste Runtime-Einrichtung muss abgeschlossen sein, bevor automatische Spracherkennung funktioniert.
- Eigene Lyrics-Ansichten in Apps oder Material Skin benötigen eine explizite [Client-API-Anbindung](CLIENT-API.md).

## Daten und Updates

Einstellungen, Modelle und Übersetzungscache liegen unter `<LMS preferences>/LyricTranslator`. Beim Deaktivieren oder Deinstallieren bleiben diese Daten erhalten. Vor Änderungen eine Sicherung des LMS-Einstellungsordners anlegen.

Neue veröffentlichte Plugin-Versionen werden über dieselbe Repository-Adresse angeboten. Ob LMS sie automatisch herunterlädt, hängt von seinen Update-Einstellungen ab. Bereits veröffentlichte ZIP-Dateien bleiben unverändert; diese GitHub-Anleitung kann zwischen Veröffentlichungen ergänzt werden.

## Lizenz und technische Dokumentation

Plugin-Code: [MIT-Lizenz](LICENSE). Fremdkomponenten behalten ihre jeweiligen Lizenzen; siehe [THIRD-PARTY.txt](THIRD-PARTY.txt).

Die [ausführliche deutsch-englische Anleitung](README.txt) beschreibt Datenordner, Grenzen und Betrieb. Die [Client-API](CLIENT-API.md) dokumentiert die Integration in andere Anwendungen.
