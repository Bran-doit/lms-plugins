# Changelog

## 0.3.0

- Show installed source languages for the selected target, including complete routes through English.
- Automatically download missing supported language models in the background. Enabled by default; disable it in settings to require manual setup. Initial runtime setup is still required for automatic language detection.
- Report `model_downloading` with `retry_after:60` to clients. Request lyrics again after setup; completion within 60 seconds is not guaranteed. Failed automatic attempts have a ten-minute cooldown.
- Add `mode:original` for original lyrics without translation or model setup, with optional timestamps. Original responses contain `translated:0` and `unchanged:1`.
- Add a client API reference covering response fields, errors and language availability.
- Add spacing between settings sections for readability.

Requires Windows x64, LMS 8.x/9.x and the enabled Music and Artist Information plugin. Existing models and settings are retained; no migration is needed. Restart LMS after updating the plugin. Translation stays local; model downloads and the upstream lyrics provider need network access.

Validation: 94 local Perl assertions including worker integration passed for this implementation; automatic Spanish model setup and original-lyrics retrieval were verified on Windows LMS. Release automation additionally checks the Python helper and package/index generation.

Includes functionality tested locally as 0.2.1 and 0.2.2, published as a minor release according to versioning rules.

## 0.2.0

- Support eight translation languages, with direct models or English as an intermediate language.
- Add automatic offline source-language detection and language selectors.
- Use German UI for German LMS settings, English otherwise.
- Provide CLI / JSON-RPC translation, status and language commands.
