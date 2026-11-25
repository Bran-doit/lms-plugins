# Search Focus changelog

## 0.6.0

- Rename the visible plugin to **Search Focus** in all languages.
- Use the LMS server language: German for DE, English for every other/unset language. Translate settings, help, warnings, validation errors and result explanations; separate caches by interface language.
- Preserve search scoring, saved aliases, module/UUID/preference identity and the LMS 9.0.3 compatibility guard.
- First public repository release with English/German instructions, automated tests, versioned ZIP and LMS index entry. Normalize the technical manifest name to SearchFocus for repository packaging.
- Full Text Search remains required for track/album/artist integration; genre integration is independent. Restart LMS after installing. Avoid duplicate manual and managed plugin copies.
- This release has automated regression and rendering coverage; no live-server deployment is claimed.

## 0.5.0

Tolerant contributor/name search, initials, typo candidates, validated person-specific aliases and explicit family-name weighting. Artists remain separate records.

## 0.4.0

Client genre searches with spelling variants, typo tolerance, compound ranking and optional compound exclusion. No full-text index expansion.

## 0.3.1

Compact settings, accessible help pop-ups and red dependency warnings.

## 0.3.0

Similarity bonus for missing words in existing results; no relaxation of normal AND matching.

## 0.2.0

Lower weights for German articles/possessives; case-aware content-word weighting and auditable exact/multiword bonuses.

## 0.1.1

Invalidate LMS result-count caches and fix settings-template character encoding.

## 0.1.0

Initial field filtering and ranked full-text candidate integration for LMS 9.0.3.