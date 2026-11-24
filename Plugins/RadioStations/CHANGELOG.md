# Changelog

## 0.9.0

First public release in Bran-doit's LMS Plugins repository.

- Browse Radio Browser stations by country and region, including the configured local country. Directory lists use alphabetical ordering and letter navigation.
- Maintain a separate Radio Favorites list under Radio, with native LMS list/cover views and a pencil opening the native Favorites editor.
- Add stream URLs manually, edit entries and reorder stations using drag-and-drop or settings-table arrows. Settings show station logos.
- Optionally recognize new radio stations in LMS Favorites and copy them automatically (default), or move them after saving. Previously processed and manually returned stations are excluded from repeat imports. Ambiguous links and podcasts are retained.
- Preserve available track artwork and use the station logo as a fallback through LMS artwork handling.
- Include English and German interface strings.

Requires LMS 8.x/9.x and its native Favorites component. Client artwork and editing capabilities depend on the client/skin. Radio detection is conservative and cannot classify every stream URL.

Existing local Radio Stations users retain their preferences and radio store; pending legacy manual entries are migrated when opened. Back up the LMS preferences before upgrading. Radio Browser can remain installed alongside Radio Stations.

Based on Radio Browser by hjelev. Native editor components derive from LMS Favorites; see LICENSE and accompanying license files.
