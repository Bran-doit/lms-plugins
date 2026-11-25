# Development and publication

- Publish only on an explicit user request. Development uploads belong on `codex/<topic>` branches; public branches must contain no secrets, user preferences, station stores or diagnostics.
- Preserve unrelated changes. Review workflow triggers before uploading.
- `main` is the publication branch. `.github/workflows/publish.yml` runs on changes to Plugins, scripts, tests or itself; workflow_dispatch also publishes.
- Each plugin's `install.xml` is its version source. Use MAJOR.MINOR.PATCH. Never replace published tags or packages with changed content; increment the version. The shared repository index is mutable.
- Before publication update plugin instructions and CHANGELOG, retain third-party licenses, run `python -m unittest discover -s tests -p 'test_*.py'`, `prove tests/radiostations-*.t`, and `python scripts/publish.py`. Python tests require numpy and py3langid; Perl tests require JSON::XS and URI.
- Releases target this GitHub repository. The stable LMS index is `https://github.com/Bran-doit/lms-plugins/releases/download/repository/repo.xml`. Packaging calculates SHA1 and updates the index only after all packages are available.
- Follow Actions to completion and verify downloadable packages, versions and index checksums. Report actual validation and remaining limitations.
- Publishing does not authorize installing or restarting a live server. Keep deployment separate.

## Plugin documentation

- Every plugin/app has a README.md in its own directory so GitHub renders a dedicated description page. The root README.md is the catalog, linking to each plugin page and its changelog.
- Keep the plugin page understandable: purpose, features, prerequisites, installation, usage/settings, limitations, updates, license and links to technical references. Preserve useful README.txt references; keep overlapping facts consistent.
- Update this documentation with feature changes and before publication. Do not invent screenshots, supported platforms or validation results.
- User-requested documentation-only website updates may go to main without publishing binaries. For the current push workflow use a dedicated documentation-only commit with [skip ci]; never use this marker to bypass tests for code or release changes.
- Documentation inside plugin folders affects future ZIP contents. Do not rebuild an already released version with changed documentation; include it in the next version. An explicit workflow_dispatch still publishes and must not be used for documentation-only work.

## Search Focus
- Supported LMS version is exactly 9.0.3. Do not broaden the manifest without verifying the internal hooks.
- Run `prove tests/searchfocus-*.t` (DBI, DBD::SQLite, Template). Keep DE and EN settings controls in parity; non-German server languages use English.
- Never upload local library exports, live diagnostics, server addresses, preferences or backups. Search Focus public sources are explicitly staged; no workspace-wide upload.
- Keep module/UUID/preferences stable. Publishing remains separate from live installation/restart.
