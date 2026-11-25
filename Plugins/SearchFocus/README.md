# Search Focus

Ranked, configurable searches for Lyrion Music Server, including tolerant name and genre matching.

[Deutsch](README.de.md) · [Changelog](CHANGELOG.md) · [License](LICENSE)

## Requirements

- **LMS 9.0.3 only.** The integration uses internal LMS interfaces and deliberately rejects other versions. No wider compatibility is claimed.
- Enable the built-in **Full Text Search** plugin for track, album, playlist, work and artist integration. Its existing index is reused, never rebuilt or modified by Search Focus.
- The separate genre extension reads the genre list and does not need Full Text Search.
- The core is Perl/SQLite without a platform-specific helper. Prior runtime validation was on Windows; other platforms have not been live-tested.

## Install

Add this address under **Settings → Plugins → Additional repositories**:

```text
https://github.com/Bran-doit/lms-plugins/releases/download/repository/repo.xml
```

Select **Search Focus**, follow LMS installation prompts and restart LMS. Configure it under **Settings → Advanced → Search Focus**. A red warning explains missing Full Text Search or inactive integration.

For earlier manually installed versions, back up the plugin and preferences, then use one installation location only. Do not leave both a manual and an extension-manager copy active. The module, plugin directory, UUID and preference namespace remain unchanged. The manifest now uses the repository-compatible technical name `SearchFocus`; the visible name is **Search Focus** in every language. Restart after upgrading.

## Language

The interface follows the **LMS server language**: German for `DE` (including German locale variants), English for all other or unset values. This applies to settings, help pop-ups, warnings, errors, preview categories and score explanations. Changing the interface language does not translate library metadata, rewrite saved aliases or change ranking. The low-weight article/possessive word list remains German.

## Settings and behavior

- **Search fields:** title, album, artists/contributors, playlist, genre, lyrics and comments. Lyrics, comments and the genre field in track search are off by default.
- **AND/OR:** all words or at least one word. Exact names/titles and multiple matches rank above weaker matches. In normal track/album search, fuzzy bonuses reorder existing candidates rather than finding typo-only new results.
- **Tolerant name search:** uses existing contributor names, including composers subject to the client's role filters. Finds names using one edit, adjacent transpositions, prefixes, initials and person-specific aliases. It affects artist results, not the track/album search fields.
- **Name aliases:** expand the editor in settings. Format: `Library name | Family name (optional) | Alias one; Alias two`. Explicit family names carry more weight than given names; unclassified names/bands have neutral word weights. Initials alone do not expand results. Chopin examples are included as editable defaults. Separate artist IDs are never merged.
- **Genre search:** `classic`, `klassic` and `klassik` are equivalent. Recognizes one edit in words of at least four characters. Standalone genres score above compound components.
- **Compound genres:** hidden by default unless explicitly queried, e.g. `classic jazz`. Disable this switch to include partial compound matches. All words are required in genre searches; entering `and` does not create an operator. Direct genre browsing by ID is unchanged.
- **Test search:** up to 30 results per category with scores. The preview does not apply client/library filters. Actual client queries retain LMS filters, counts and pagination. The genre preview uses the new scoring even if genre client integration is off.

Hover, focus or tap **?** for details. Escape closes a help pop-up. Invalid alias entries prevent partial settings saves. Disabling the main switch restores the original search; no index rebuild is needed.

## Limits and privacy

Queries are limited to 256 characters and 12 words. No external search service is used. Music files, tags, persistent index tables and contributor IDs are unchanged. There is no automatic artist merging or general semantic/synonym recognition. Default name/genre switches are enabled, but client sorting and role filters can affect displayed results. Playlists can still be alphabetic. There is no claim to replace every third-party client search route.

## Updates and verification

The version in `install.xml` is authoritative. This repository builds immutable versioned ZIPs, verifies tests and generates the LMS index/checksum after packages are published. Version 0.6.0 adds German/English presentation and publication metadata; it does not expand the supported LMS versions or change search scoring.

Run from the repository root: `prove tests/searchfocus-*.t` (DBI, DBD::SQLite, Template and Test::More required). Tests cover ranking, filters/pagination adapters, settings validation, DE/EN/fallback rendering, escaping and language-independent scores. Runtime validation of earlier search features is not a claim that this release was installed on a live server.

## License

MIT. [Third-party/runtime notes](THIRD-PARTY.txt). LMS and its dependencies are not bundled and retain their own licenses.