# TODO/FIXME comment sweep — 2026-05-20

## Methodology

Grepped for `TODO` / `FIXME` / `XXX` / `HACK` markers across every Swift file
in the four primary targets:

```
grep -rnE "//.*(TODO|FIXME|XXX|HACK)[\s:]" \
  OffScript/ OffScriptTests/ OffScriptUITests/ OffScriptWidgets/ \
  --include='*.swift'
```

Followed up with a broader case-insensitive sweep and a lowercase-variant
sweep to make sure nothing was hiding behind unconventional capitalization
or non-`//` comment styles (`///`, `/* */`, MARK lines).

For each finding I read 5+ lines of context, then cross-referenced the
relevant code path and `git log` to decide whether the gap is real, done,
intentional, or unclear.

Classifications:
- **STALE** — work has been done since; comment is just lingering text.
- **STILL-ACTIVE** — gap is real and unresolved.
- **CONTEXT-BOUND** — intentional/known limitation that's documented inline.
- **AMBIGUOUS** — needs human review.

## Summary

- **Total findings: 1**
- STALE (recommend delete): **1**
- STILL-ACTIVE (promote to tracked work): 0
- CONTEXT-BOUND (known limitation, leave): 0
- AMBIGUOUS (needs human review): 0

The codebase is effectively free of TODO/FIXME/XXX/HACK markers. This is
unusually clean for an app of OffScript's surface area (~30+ subsystems,
145KB+ LibraryView, full CarPlay + widget + Live Activity stack). The one
finding is a documentation drift, not real work.

## Findings by area

### Playback

None.

### Downloads

None.

### Search / Discovery

None.

### Recommendations

None.

### UI / Views

None.

### Tests

None across `OffScriptTests/`, `OffScriptUITests/`.

### Models

None.

### Other — Widgets

| file:line | classification | comment | recommendation |
|---|---|---|---|
| `OffScriptWidgets/NowPlayingWidget.swift:7` | **STALE** | `/// `offscript://player` URL (handled in OffScriptApp.onOpenURL — TODO).` | Replace TODO with accurate pointer. The deep-link IS wired — see below. |

#### Detail — the one stale TODO

The widget doc-comment claims the `offscript://player` URL is "handled in
OffScriptApp.onOpenURL — TODO", implying the handler hasn't been written.

Reality:
- `ContentView.swift:166` attaches `.onOpenURL { url in DeepLinkRouter.handle(url, in: modelContext) }`.
- `DeepLinkRouter.swift:60-67` handles `host == "player"` by setting
  `PlaybackController.shared.isPlayerPresented = true` when something is
  loaded.
- `NowPlayingWidget.swift:17` itself sets `.widgetURL(URL(string: "offscript://player"))`.

The full deep-link grammar (`player`, `episode/<uuid>`, `podcast/<uuid>`,
`tab/<name>`) is implemented and tested. The TODO is documentation drift
— it was likely written before `DeepLinkRouter` landed (commit `a5dc59a`)
and never updated, even though three subsequent commits touched the
router (`5ef1ca6`, `d0dd62b`, `3000d52`).

## STALE follow-up — recommended deletions

A single-line copy-edit in a follow-up commit:

- `OffScriptWidgets/NowPlayingWidget.swift:7` — change
  `(handled in OffScriptApp.onOpenURL — TODO)` to
  `(handled by DeepLinkRouter via ContentView.onOpenURL)`.

This is a low-risk doc-only change. Recommend folding into the next
widget-adjacent commit rather than its own.

## STILL-ACTIVE follow-up — promoted work items

None. There are no unresolved inline TODOs to promote.

## Strategic finding

For a project of OffScript's size and apparent feature breadth — full
CarPlay scene delegate, background transcription, live activities,
SwiftData + iCloud, Spotlight, intents, widgets, batch import, OPML — a
**total of one TODO** is remarkable. The development culture here clearly
favors either fixing things in-line or promoting concerns to the
`docs/superpowers/audits/` directory (17+ audit docs dated 2026-05-19 and
2026-05-20 already exist) rather than leaving inline markers.

This is the inverse of the typical pattern: instead of TODO density
revealing a stressed subsystem, the *absence* of TODOs combined with the
*presence* of a structured audit-doc workflow suggests the team has
already externalized known-issue tracking. Future audits looking for
unresolved gaps should query the audit-doc index, not `grep -r TODO` —
the latter will continue to return ~zero results by design.

The one stale finding is also informative: it lives in `OffScriptWidgets/`,
the only target outside the main app module. Cross-module documentation
drift is the residual risk pattern worth watching as the widget surface
expands (Smart Stack, Control Center, lock-screen interactive widgets).
