# Search Focus

Konfigurierbare und gewichtete Suche für Lyrion Music Server mit toleranter Namens- und Genresuche.

[English](README.md) · [Änderungen](CHANGELOG.md) · [Lizenz](LICENSE)

## Voraussetzungen und Installation

Unterstützt wird ausschließlich **LMS 9.0.3**. Interne Schnittstellen sind versionsgebunden. Für Titel, Alben, Interpreten, Werke und Playlists muss das eingebaute Plugin **Volltextsuche** aktiviert sein. Die separate Genre-Erweiterung benötigt es nicht. Der Perl-/SQLite-Code enthält keinen plattformspezifischen Helfer; die bisherige Laufzeitprüfung erfolgte unter Windows, andere Plattformen sind nicht live geprüft.

Unter **Einstellungen → Plugins → Zusätzliche Repositories** eintragen:

```text
https://github.com/Bran-doit/lms-plugins/releases/download/repository/repo.xml
```

**Search Focus** auswählen, LMS-Installationshinweisen folgen und LMS neu starten. Das Menü befindet sich unter **Einstellungen → Erweitert → Search Focus**. Fehlende Volltextsuche oder Client-Anbindung wird rot angezeigt.

Bei älteren manuellen Installationen zuerst Plugin und Einstellungen sichern und nur einen Installationsort verwenden: keine parallelen manuellen und vom Erweiterungsmanager verwalteten Kopien aktiv lassen. Modul, Verzeichnis, UUID und Einstellungs-Namensraum bleiben unverändert. Der technische Manifestname für die Veröffentlichung lautet jetzt `SearchFocus`, der sichtbare Name in allen Sprachen **Search Focus**. Nach dem Update LMS neu starten.

## Sprache

Die **LMS-Serversprache** entscheidet: Deutsch bei DE einschließlich deutscher Sprachvarianten, sonst Englisch. Menü, Hilfen, Warnungen, Fehlermeldungen, Vorschaukategorien und Trefferbegründungen sind übersetzt. Bibliotheksnamen, gespeicherte Varianten und Suchbewertung bleiben unverändert. Die Wortliste für schwach gewichtete Artikel und Possessivformen bleibt deutsch.

## Bedienung

- Suchfelder getrennt schalten: Titel, Albumname, Interpreten/Mitwirkende, Playlistname, Genre, Lyrics und Kommentare. Lyrics, Kommentare und Genre in der Titelsuche sind standardmäßig aus.
- UND verlangt alle Wörter, ODER mindestens eines. Exakte vollständige Namen/Titel und mehrere passende Wörter werden bevorzugt. Der Ähnlichkeitsbonus bei Titel-/Albumsuchen sortiert bestehende Treffer; er findet dort keine neuen reinen Tippfehlertreffer.
- **Tolerante Namenssuche:** neue Interpreten-/Mitwirkendentreffer über Tippfehler, Wortanfänge, Initialen und gezielte Varianten. Komponisten werden berücksichtigt, soweit der Client-Rollenfilter sie zulässt. Dies erweitert nicht die Titel-/Albumsuche über Namen.
- **Personenspezifische Varianten:** `Vorhandener Name | Nachname (optional) | Variante eins; Variante zwei`. Nachnamen werden nur bei ausdrücklicher Zuordnung stärker gewichtet; sonst sind Namenswörter neutral. Initialen allein erweitern die Suche nicht. Chopin-Beispiele sind editierbar vorbelegt. Einträge werden nicht zusammengeführt.
- **Genresuche:** classic/klassic/klassik gelten gleichwertig. Ein Buchstabenfehler ab vier Zeichen ist zulässig. Eigenständiges Genre vor erstem und weiteren Mischbestandteilen.
- **Mischgenres nur gezielt:** standardmäßig an. `classic jazz` findet entsprechende Mischgenres, `classic` allein nicht. Alle Wörter sind in der Genresuche erforderlich; „und“ ist kein Operator. Direktes Öffnen per Genre-ID bleibt möglich.
- **Testsuche:** bis zu 30 Treffer je Kategorie mit Begründung, ohne Client-/Bibliotheksfilter. Normale Client-Abfragen behalten LMS-Filter, Trefferzählung und Pagination. Die Genre-Vorschau zeigt die neue Logik auch bei ausgeschalteter Genre-Anbindung.

Hilfen erscheinen beim Darüberfahren, Fokussieren oder Antippen von **?**; Escape schließt sie. Fehlerhafte Varianten verhindern das Speichern aller Änderungen. Ausschalten des Hauptschalters stellt die ursprüngliche Suche wieder her.

## Grenzen und Datenschutz

Maximal 256 Zeichen und 12 Suchwörter. Keine externen Suchdienste, keine Änderung von Musikdateien, Tags, dauerhaften Indextabellen oder Interpreten-IDs. Kein Indexneuaufbau nötig. Keine automatische Künstlergruppierung oder allgemeine Bedeutungsanalyse. Neue Namens-/Genre-Schalter sind standardmäßig aktiviert. Client-Sortierung und Rollenfilter können die Darstellung beeinflussen; Playlists können alphabetisch bleiben. Nicht jeder Suchweg eines Drittanbieter-Clients wird garantiert abgedeckt.

## Updates, Tests und Lizenz

`install.xml` ist die Versionsquelle. Die Veröffentlichung erzeugt versionierte ZIPs, Prüfsummen und einen gemeinsamen LMS-Index. Version 0.6.0 ergänzt Übersetzung und Veröffentlichungsmetadaten, keine neue Suchbewertung oder weitere LMS-Versionen.

Tests: `prove tests/searchfocus-*.t` im Repository-Hauptverzeichnis (DBI, DBD::SQLite, Template und Test::More). Geprüft werden Bewertung, Schnittstellen, Einstellungen, deutsch/englische Vorlagen, Sprachfallback und Escaping. Eine frühere Live-Prüfung der Suchfunktionen ist keine Installation dieses Releases auf dem laufenden Server.

MIT-Lizenz. [Hinweise zu Fremdkomponenten](THIRD-PARTY.txt). LMS und seine Laufzeitbibliotheken werden nicht mitgeliefert.