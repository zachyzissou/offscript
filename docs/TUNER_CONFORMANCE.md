# Tuner UI Conformance Audit

A surface-by-surface log of what was checked, what is intentionally
native, and where the Tuner OLED vocabulary applies. Companion to the
design bible in [`CLAUDE.md`](../CLAUDE.md). Update this file alongside
any change that touches the surfaces below.

## Tuner Vocabulary (the rules being enforced)

- **Background**: `offscriptStudioBlack` (pure black). Every screen.
- **Primary text / accent / hairline**: `offscriptPaperWhite`,
  `offscriptSignalYellow`, `offscriptHairline` (white @ 8% alpha).
  Function-coded accents (`offscriptFnRecord`, `offscriptFnMode`,
  `offscriptFnInfo`, `offscriptFnMute`) only for state communication.
- **Typography**: `TunerLabel`/`TunerTag`/`TunerRailReasonTag` for every
  mono readout, eyebrow, status badge. `.system(size:..., design: .default)`
  for body and titles.
- **Surfaces**: flat black + 1pt hairline rectangles. Sharp corners
  (artwork tiles 3pt; everything else 0pt). No `RoundedRectangle` outside
  artwork primitives in `AppTheme.swift`. No Capsule, no Material, no
  Liquid Glass on app-authored controls.
- **Modal/sheet chrome**: `tunerModalSurface()` modifier — never the
  default sheet card.
- **Navigation chrome**: `.toolbarBackground(Color.offscriptStudioBlack, …)`
  + `.toolbarColorScheme(.dark, …)` on every `NavigationStack`-backed
  screen. Detail back navigation uses `TunerInlineBackButton`, never the
  native `Back` chrome.
- **Action keys**: hairline rectangles with mono `TunerLabel`. Visible
  size scales freely; hit target stays at 44pt × 44pt minimum.

## Surface Audit

| Surface | File | State | Notes |
|---|---|---|---|
| Home (rails, retune, settings) | `OffScript/HomeView.swift` | ✅ Tuner-conformant | Toolbar uses Tuner background; settings/retune are inline hairline buttons; no `.searchable`, no `Menu`, no native pull-to-refresh. |
| Hero rec card | `OffScript/HomeView.swift` (HeroTunerCard) | ✅ Tuner-conformant | All layout via VStack + hairlines; reason rendered via wrapping `TunerTag`; play/queue keys are hairline rectangles. |
| Tuner rail card | `OffScript/HomeView.swift` (TunerRailCard) | ✅ Tuner-conformant | 168pt artwork @ 3pt corner; `TunerRailReasonTag` for reason; signal-yellow play key. |
| Discovery card | `OffScript/HomeView.swift` (discoveryCard) | ✅ Tuner-conformant | TUNE/TUNED key uses signal-yellow / fn-mode hairline rectangle. |
| Library directory | `OffScript/LibraryView.swift` | ✅ Tuner-conformant | Lazy section/row/separator stack; `tunerSearchField` instead of `.searchable`; alphabet rail and ATTN/UNPLAYED/IN PROGRESS/DOWNLOADED filters all use Tuner keys. |
| Library — Podcast Detail | `OffScript/LibraryView.swift` (PodcastDetailView) | ✅ Tuner-conformant | Inline `TunerInlineBackButton`; episode rows use `PodcastEpisodeTunerRow` (#145 fix); no `.searchable`. |
| Library — Episode Detail | `OffScript/EpisodeDetailView.swift` | ✅ Tuner-conformant | Spec-sheet vocabulary; toolbar background is `offscriptStudioBlack`; back chrome is `EpisodeDetailBackButton` per UI-test assertions. |
| Library Import Sheet | `OffScript/LibraryImportSheet.swift` | ✅ Tuner-conformant (with intentional native exceptions) | Tuner header + DONE inline; modes (menu / paste URL / OPML / batch import) all use Tuner keys. Native exceptions: `.fileImporter` for OPML pick, `UIActivityViewController` (`ShareSheet`) for OPML export. Both are Apple-supplied chrome that cannot be replaced without harming accessibility or system file integration. |
| Search | `OffScript/SearchView.swift` | ✅ Tuner-conformant | Custom `tunerSearchField` instead of `.searchable`; results render through `OffScriptArtworkView` + Tuner labels. |
| Queue | `OffScript/QueueView.swift` | ✅ Tuner-conformant | `EpisodeCompactCard` rows; reorder is inline Tuner keys, not long-press context menu. |
| Player (full) | `OffScript/PlayerView.swift` | ✅ Tuner-conformant | Spec-sheet sections (PLAYER · NOW PLAYING / UP NEXT / WHAT'S NEXT / CONTROLS · TRANSPORT); inline dismiss key, Tuner scrubber, sleep timer / speed grid via `TunerRatePicker`. |
| MiniPlayer | `OffScript/MiniPlayer.swift` | ✅ Tuner-conformant | Flat docked strip, top hairline + 2pt signal-yellow progress rail, sharp signal-yellow play key. |
| Settings | `OffScript/SettingsView.swift` | ✅ Tuner-conformant | Header eyebrow + DONE inline; toggles, sign-out confirmation, default-rate picker all Tuner-styled. UI smoke covers Home and Library entry points plus the present→dismiss→re-present cycle (#114). |
| Onboarding flow | `OffScript/OnboardingFlowView.swift` | ✅ Tuner-conformant (with intentional native exception) | Power-on screen, genre picker, channel picker, ImportProgressView all Tuner. Native exception: `ASAuthorizationAppleIDButton` for Sign in with Apple — Apple requires the system button and forbids visual modification (HIG: Sign in with Apple). |
| Import Progress | `OffScript/ImportProgressView.swift` | ✅ Tuner-conformant | Per-feed status strip with Tuner labels; retry/continue actions are Tuner keys. |
| In-app Safari | `OffScript/AppTheme.swift` (`SafariView`) | ✅ Apple-supplied | `SFSafariViewController` is the required path for in-app web (per `CLAUDE.md`: "Stay in-app — never open external links without `SFSafariViewController`"). |

## Intentional Native Exceptions

These controls remain native by design. None should be replaced without
explicit owner sign-off and an HIG/accessibility justification.

| Control | Where | Why Native |
|---|---|---|
| `ASAuthorizationAppleIDButton` | `OnboardingFlowView.swift:216` | Sign in with Apple requires the system button. Apple HIG forbids custom Sign in with Apple controls. |
| `UIActivityViewController` (via `ShareSheet`) | `LibraryImportSheet.swift:488` | OPML export hands a file to the system share sheet so the user can route it through any installed app. A custom share UI cannot enumerate the system share targets. |
| `.fileImporter` | `LibraryImportSheet.swift:73` | OPML import uses the system document picker for sandboxed file access. A custom picker would lose iCloud Drive / Files-app integration. |
| `SFSafariViewController` (via `SafariView`) | `AppTheme.swift:64` | In-app web preview for episode show-notes and external podcast links. The bible mandates `SFSafariViewController` over a web view we ship ourselves. |
| `MPNowPlayingInfoCenter` / `MPRemoteCommandCenter` lockscreen + Now Playing UI | system | The lock screen, Now Playing widget, and CarPlay lockscreen are owned by the OS. The app feeds metadata; the OS draws the UI. |
| Live Activity & Dynamic Island templates | `OffScriptWidgets/` | `WidgetKit`/`ActivityKit` templates are constrained by Apple. Visual customization is limited to the supported presentation styles. |

## Verification

Existing automated coverage pinning Tuner conformance:

- `OffScriptUITests/testTunerDetailScreensUseInlineBackChrome` — asserts
  podcast and episode detail use `*BackButton` rather than the system
  `Back` button.
- `OffScriptUITests/testSettingsPanelOpensFromHome`,
  `testSettingsPanelOpensFromLibrary`,
  `testSettingsPanelDismissAndReopenCycleStaysStable` — assert the
  Settings sheet uses `SETTINGS · CONFIG PANEL` Tuner header + `Close
  settings` inline DONE key.
- `OffScriptUITests/testPostOnboardingShellSmoke` — asserts the custom
  Tuner tab bar (`Home`, `Library`, `Queue`, `Search` buttons) resolves,
  not native `TabView` chrome.

When adding or modifying an app surface:

1. Land the change with the Tuner primitives (`TunerLabel`, `TunerTag`,
   `TunerRailReasonTag`, `OffScriptArtworkView`, `tunerModalSurface`).
2. Update the relevant row in this file in the same PR.
3. If a new native exception is introduced, add it to **Intentional
   Native Exceptions** with the HIG/accessibility justification.
