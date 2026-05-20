# Pre-release VoiceOver walk — 2026-05-19

## Baseline (before audit)

- Branch: `release/2.4.0-audit` cut from `main` @ `1316f3b`
- MARKETING_VERSION: 2.3.11
- CURRENT_PROJECT_VERSION: 2026043004
- Simulator: iPhone 17 Pro · iOS 26.5 (UDID `F623EB2A-1CF4-405E-9583-6B0EE2053FDE`)
- Toolchain: Xcode 26.5 (17F42)
- Build: succeeded
- Compile warnings (unique): 0
- Unit tests: 110/111 passing (OffScriptTests target only; 1 pre-existing failure: `feedSyncFastBatchImportUsesCheapProfilesAndSkipsExternalChapters` at OffScriptTests.swift:2776 — `profile.tags` empty when expected non-empty)
- UI tests: deferred to Phase 3 (5× per test reliability check)

### Baseline notes

- `Config/Secrets.xcconfig` is gitignored and was missing locally; created from `Secrets.xcconfig.example` with a placeholder `SENTRY_DSN` so the local debug build can link. Xcode Cloud materializes the real value via `ci_post_clone.sh`, so no commit is needed.

## Surfaces

_Filled in during Phase 2 — VoiceOver functional verification._
