# Radio Stations

An independent Radio Browser plugin for Lyrion Music Server, based on [Radio Browser by hjelev](https://masoko.net/lyr-radio-browser/).

## Installation

Requires LMS 8.x or 9.x with the native Favorites component enabled. Add this URL in **Settings → Plugins → Additional repositories**:

```text
https://github.com/Bran-doit/lms-plugins/releases/download/repository/repo.xml
```

Select **Radio Stations**, apply the changes and follow LMS's restart instructions. Open **Radio → Radio Stations** to browse countries, regions, genres and stations. Configure a two-letter country code for local stations. The interface includes English and German translations.

## Radio Favorites

Enable the Radio Favorites folder in the plugin settings. Optionally enable automatic recognition of new radio entries in the general LMS Favorites. Copying is the default; moving removes an original only after successful storage. Previously processed URLs and manually returned entries are not imported repeatedly. Unknown audio links and podcasts are retained.

Add a stream URL and optional name in settings. Use the table arrows to reorder entries, or open the pencil in Radio Favorites to use the native LMS editor. This is a flat list without subfolders or file import/export. Station logos appear in settings and supported browsing views. Available track artwork takes precedence over the station logo; client support varies.

Data is stored separately in `radiostations-favorites.json` in the LMS preferences directory. Back up that directory before upgrading. Existing Radio Stations preferences remain in use; legacy pending manual entries are migrated on opening. The original Radio Browser plugin can coexist with this plugin.

[Deutsche Anleitung](README.txt) · [Release history](CHANGELOG.md)

## License

The combined distribution uses GPL version 2. Original Radio Browser MIT notices and LMS Favorites notices are retained. See [LICENSE](LICENSE), LICENSE-MIT.txt, LICENSE-GPL-2.0.txt and LMS-LICENSE.txt.
