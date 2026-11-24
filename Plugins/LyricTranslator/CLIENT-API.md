# Lyric-Translator client API

Applies to plugin version **0.3.0**. This reference ships with the plugin and
its release ZIP. It describes a plugin-specific API over the standard LMS
CLI / JSON-RPC transport; it is not a built-in LMS lyrics standard.

## Connection and availability

Use the existing LMS server connection, authentication and port. For JSON-RPC,
POST JSON to `/jsonrpc.js`. No separate translation service port is needed.
Query `lyrictranslator status` to obtain the installed `version`. A missing
command means the client cannot rely on this plugin being available.
Original mode is supported starting with 0.2.1. The status `ready` field
describes translation readiness: it is not a prerequisite for original mode.
Music and Artist Information (MusicArtistInfo) must be enabled for both modes.

## Original lyrics

Example request (replace the example track ID with a real library track ID):

```json
{
  "id": 1,
  "method": "slim.request",
  "params": ["", ["lyrictranslator", "lyrics", "track_id:123", "mode:original"]]
}
```

Illustrative `result` object, using invented example text:

```json
{
  "mode": "original",
  "lyrics": "An example line.\nAnother example line.",
  "original": "An example line.\nAnother example line.",
  "title": "Example Song",
  "artist": "Example Artist",
  "translated": 0,
  "unchanged": 1
}
```

The original mode skips translation, language detection, model setup and the
translation queue. `source` and `target` request parameters are ignored.
No source language is guessed. Translation metadata such as `source`,
`target`, `cached`, `via`, `detected` and `confidence` is absent in this mode.
The upstream lyrics provider may need Internet access.

## Lyrics request parameters

| Parameter | Meaning |
| --- | --- |
| `mode:original` | Fetch original lyrics without translation. |
| `mode:translated` | Translate lyrics; default when `mode` is omitted. |
| `track_id:123` | Identify an LMS library track. |
| `artist:Example`, `title:Example` | Alternative lookup by artist and title. |
| `album`, `url`, `duration` | Optional lookup hints forwarded to MusicArtistInfo. |
| `timestamps:1` | Retain available LRC timestamps. Does not create timestamps. |
| `timestamps:0` | Return plain lyrics; default when omitted. |
| `source:auto` or language code | Translation source; defaults to saved setting. |
| `target:de` or other language code | Translation target; defaults to saved setting. |

Without track parameters, MusicArtistInfo resolves the current track for the
player ID passed as the first `params` item. Supply that player's ID instead
of the empty string in this case.

## Successful response fields

| Field | Meaning |
| --- | --- |
| `lyrics` | Text to display, in the requested mode and timestamp format. |
| `original` | Original provider text. In original mode identical to `lyrics`. In translation mode may retain timestamps even when `lyrics` is plain. |
| `mode` | Requested mode, `original` or `translated`. |
| `translated` | Numeric `1` when translation was performed, `0` when the text was returned unchanged. |
| `unchanged` | `1` for unchanged text; otherwise may be absent. |
| `title`, `artist` | Track metadata; may be empty strings. |
| `source`, `target` | Resolved language codes in translation mode. |
| `cached` | Translation cache indicator, when provided. |
| `via` | Intermediate language, e.g. `en`, when provided. |
| `detected`, `confidence` | Detection metadata when provided. Confidence is not a calibrated probability. |

**Do not infer the requested mode from `translated` alone.** `translated:0`
also occurs with `mode:translated` when the lyrics are already in the target
language. Check `mode` to distinguish these cases. A translated result may
come from the cache; `translated:1` does not mean a new computation occurred.
Clients should tolerate absent optional fields and additional future fields.

## Errors

Check for `result.error` before interpreting success fields. An optional
`error_code` provides a machine-readable reason, for example `invalid_mode`.
Not every error has a code. Error messages are localized; do not parse their
wording. Provider failure, missing lyrics and lookup timeout are errors, not
successful empty lyric responses. Transport/JSON-RPC errors must also be handled.
There is no cloud translation fallback. In 0.3.0, missing supported models
are downloaded in the background when the `autoDownload` setting is enabled
(default). A pending setup returns `error_code: "model_downloading"` and
`retry_after: 60` (seconds). Retry the request after that interval; setup may
take longer. Do not treat this response as successful lyrics. Original mode
remains available and never triggers downloads. Automatic detection needs
initial runtime setup before it can identify which model is missing.
Automatic attempts for a pair have a ten-minute cooldown to limit repeated
downloads after failure. Manual setup can be used to retry sooner.

## Other commands

```text
lyrictranslator status
lyrictranslator languages
```

`status` reports the plugin version, translation readiness and selected pair.
From 0.3.0, `auto_download` is 0 or 1 and `available_sources` is an array of
`{code,name}` for installed source languages to the selected target. Routes
through English are included only when all required models are installed.
The target itself is excluded because it requires no translation. An empty
array means no translation source is ready. Names follow the LMS UI language.
`languages` returns `count` and `languages_loop`, each item containing `code`,
localized `name`, and numeric `source_only`. `auto` is source-only.

## Integration note

This file documents the contract for developers; clients do not automatically
discover or implement it. A client must explicitly call the commands above.
There is currently no separate API-discovery endpoint or documentation URL.

Deutsch: Bei `mode:original` stehen die Original-Lyrics in `lyrics` und
`original`; `translated` ist 0 und `unchanged` ist 1. Auch ein bereits in der
Zielsprache vorliegender Text kann `translated:0` haben. Deshalb zusätzlich
`mode` auswerten. Diese Dokumentation liegt im Plugin-Ordner und im Release-ZIP.
