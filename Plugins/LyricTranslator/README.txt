Lyric-Translator 0.2.0

DEUTSCH
Liedtexte lokal übersetzen, ohne API-Schlüssel oder Übersetzungsgebühren.
Windows x64, LMS 8.x/9.x, mit aktivem Music and Artist Information.

Einstellungen > Erweitert > Lyric-Translator:
- Ausgangssprache: Automatisch erkennen oder manuell wählen.
- Zielsprache: Deutsch, Englisch, Französisch, Italienisch, Niederländisch,
  Portugiesisch, Russisch oder Spanisch.
- „Ausgewählte Sprachen einrichten“ speichert die Auswahl und lädt die
  benötigten Modelle. „Einstellungen speichern“ ändert nur die Auswahl.
- Originaltext auf Wunsch unter der Übersetzung anzeigen.

Die Oberfläche, Menüs und eigenen Meldungen sind bei LMS-Sprache DE Deutsch,
bei jeder anderen LMS-Sprache Englisch. Die Übersetzungssprache ist davon
unabhängig. Die vorhandene Auswahl Englisch -> Deutsch bleibt beim Upgrade
erhalten, sofern sie bereits gespeichert ist.

Automatische Erkennung läuft lokal auf dem Liedtext. Kurze, unsichere oder
erkennbar gemischtsprachige Texte verlangen eine manuelle Auswahl. Bereits
in der Zielsprache vorliegende Texte bleiben unverändert. Erkennt der Dienst
eine unterstützte Sprache ohne installiertes Modell, meldet er die fehlende
Kombination. Der Einrichtungsbutton ergänzt dann die Modelle der zuletzt
erkannten Sprache. Weitere erkannte Sprachen können noch nicht übersetzt
werden. Erkennung ist eine Schätzung, keine Garantie.

Zum Lesen: Titelinformationen > „Liedtext übersetzen: …“.
MusicArtistInfo liefert den Originaltext. LRC-Zeitmarken, Zeilen und Leerzeilen
bleiben erhalten. Sprachpaare ohne direktes Modell verwenden Englisch als
Zwischensprache; dabei kann Qualität verloren gehen. Keine Änderungen an
Musikdateien, Datenbank, MusicArtistInfo oder bestehenden App-Lyrics-Reitern.

ENGLISH
Translate lyrics locally, without an API key or translation fees.
Requires Windows x64, LMS 8.x/9.x and Music and Artist Information.

Settings > Advanced > Lyric-Translator offers a source-language dropdown
(automatic detection or manual selection) and a target-language dropdown.
Supported: Dutch, English, French, German, Italian, Portuguese, Russian, Spanish.
“Set up selected languages” saves the pair and installs its required models.
The standard Save Settings button saves the selection without downloading.

The add-on uses German UI only when the LMS server language is DE; all other
server languages use English. This is independent of the translation pair.
Existing explicitly saved language preferences are preserved on upgrade.

Automatic language detection is entirely local. Short, uncertain and detected
mixed-language lyrics require manual selection. Lyrics already in the target
language are returned unchanged. A missing model produces a clear error;
the setup button can install models for the last detected supported source.
Unsupported detected languages are reported instead of forced to a supported
language. Detection remains an estimate and can make mistakes.

Open Track information > “Translate lyrics: …”. The original lyrics come
from MusicArtistInfo. Line breaks and LRC timestamps are retained. Pairs
without a direct model use English as an intermediate language, which may
reduce quality. Each of the fourteen included model directions is smoke-tested.

INSTALLATION / LOCAL DATA
Copy LyricTranslator into the LMS Plugins directory and restart LMS.
Open its settings and use the setup button. Setup runs in the background;
reopen the settings page to see progress. Windows x64 only, no GPU required.
The private CPython runtime, engine, detector and required Argos models are
downloaded once. No system Python install, API account, HTTP listener or
separate Windows service. Downloads are pinned with SHA256 in downloads.json.
Additional models are installed on demand, not all at once. Existing models
are retained, including the 0.1 English-German installation in model/.
English-German with detection needs about 132 MB initially; other pairs vary.

Data folder: <LMS preferences>/LyricTranslator
  runtime/             private Python and libraries, including language detector
  runtime-ready.json   successful detector/runtime setup
  models/<from>-<to>/  individually installed models and readiness markers
  model/, ready.json   preserved legacy English-German model
  cache/               up to 1000 translations, keyed by pair, text and model hashes
  jobs/                temporary file-based requests; removed after completion
  setup-status.json    language-neutral status code, rendered in current UI language
  setup.log            diagnostic details (third-party errors can be in English)
  downloads/           verified packages retained for setup/repair

Translation and detection processes block Python socket/network operations.
Only setup downloads models; MusicArtistInfo may still fetch original lyrics
online. One translation process at a time, eight distinct queued requests;
identical requests for the same pair share one job. Per-process timeout:
180 seconds; original lookup: 90 seconds. Up to 60000 characters/1200 lines.
Lyrics are translated line by line to preserve timing; context can be lost.
Disabling/uninstalling the plugin retains its data. Remove the data folder
after disabling for full removal. Interrupted jobs may leave files in jobs/.

CLIENT API (normal LMS CLI / JSON-RPC, no separate service port)
  lyrictranslator lyrics track_id:123 timestamps:1
  lyrictranslator lyrics track_id:123 source:auto target:fr timestamps:1
  lyrictranslator lyrics artist:Example title:Example source:en target:de

JSON-RPC POST /jsonrpc.js:
  {"id":1,"method":"slim.request","params":["PLAYER_ID",
    ["lyrictranslator","lyrics","track_id:123","source:auto","target:fr","timestamps:1"]]}

Omit source/target to use the saved settings. Without track parameters,
MusicArtistInfo resolves current playback for the supplied player.
Result: lyrics, original, title, artist, source (resolved code), target,
translated (0 when already in target language), cached, via ("en" for a pivot),
detected, confidence, unchanged. Confidence is the detector's normalized
score, not a calibrated probability of correctness.
Without timestamps:1, lyrics is plain translated text.
On failure: error; worker errors also include error_code and known source/target.
There is no silent cloud fallback and no automatic model download on a lyrics query.

  lyrictranslator status
Returns current selected pair, readiness, localized status, last detected
language name, runtime readiness, version and data folder.
  lyrictranslator languages
Returns languages_loop [{code,name,source_only}], count. "auto" is source-only.
The native LMS track-information menu requires no special client integration.
Dedicated Material Skin or app lyrics panels must explicitly call this API.

LICENSES
Plugin code: MIT (LICENSE). Third-party packages retain their licenses in
the extracted runtime/model folders; see THIRD-PARTY.txt. The worker uses
CTranslate2/SentencePiece directly, not the Argos Python application.
