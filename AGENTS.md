# Development and publication

- Publish only on an explicit user request. Development uploads belong on `codex/<topic>` branches; public branches must contain no secrets, user preferences, station stores or diagnostics.
- Preserve unrelated changes. Review workflow triggers before uploading.
- `main` is the publication branch. `.github/workflows/publish.yml` runs on changes to Plugins, scripts, tests or itself; workflow_dispatch also publishes.
- Each plugin's `install.xml` is its version source. Use MAJOR.MINOR.PATCH. Never replace published tags or packages with changed content; increment the version. The shared repository index is mutable.
- Before publication update plugin instructions and CHANGELOG, retain third-party licenses, run `python -m unittest discover -s tests -p 'test_*.py'`, `prove tests/radiostations-*.t`, and `python scripts/publish.py`. Python tests require numpy and py3langid; Perl tests require JSON::XS and URI.
- Releases target this GitHub repository. The stable LMS index is `https://github.com/Bran-doit/lms-plugins/releases/download/repository/repo.xml`. Packaging calculates SHA1 and updates the index only after all packages are available.
- Follow Actions to completion and verify downloadable packages, versions and index checksums. Report actual validation and remaining limitations.
- Publishing does not authorize installing or restarting a live server. Keep deployment separate.
