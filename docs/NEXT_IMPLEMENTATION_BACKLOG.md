# OffScript Roadmap and Implementation Backlog

This roadmap mirrors the open GitHub issue backlog so the repo has a durable
source of truth even when the GitHub Project roadmap view is not accessible
from automation. Priorities reflect the current release state as of
2026-04-30.

## Agent Readiness

This backlog is safe for a senior autonomous agent that can inspect code,
verify assumptions, and push PRs through Copilot review. It is not meant to be
executed title-only.

Every open roadmap issue now has an `Agent execution contract` in GitHub and
one of these routing labels:

- `agent:low-thinking-ready`: constrained implementation agents can work one
  issue at a time by following the runbook.
- `agent:needs-spec`: tighten the issue before implementation.
- `agent:senior-required`: keep with a senior agent or owner-led workflow.

For low-thinking implementation runs, start from
[`docs/AGENT_EXECUTION_RUNBOOK.md`](AGENT_EXECUTION_RUNBOOK.md), pick one issue
with `agent:low-thinking-ready`, and require the agent to include:

1. the issue number and lane;
2. the exact files it expects to touch;
3. the verification command it will run;
4. the PR title/body it will use;
5. whether the change needs an `Unreleased` changelog entry or is already
   covered by an existing one.

If an issue does not have enough context to identify files, acceptance
criteria, verification, and non-goals, upgrade the issue first instead of
starting implementation.

Label prefilter:

```sh
gh issue list \
  --state open \
  --label "agent:low-thinking-ready" \
  --search '-label:"agent:senior-required"'
```

After that prefilter, confirm the selected issue is `Ready` in the OffScript
project. If it is still in Backlog, a senior/controller agent should either
move it to Ready or define the first narrow slice before handing it to a
low-thinking implementation agent.

### Low-Thinking Ready Queue

Use these for constrained implementation agents. Prefer the `Ready` items first;
Backlog items are valid after selecting the first narrow slice from the issue
contract.

- #105 Speed up large OPML import for real libraries
- #106 Reduce onboarding subscription latency
- #107 Make Library performant with 250+ subscribed shows
- #109 Complete full Tuner UI conformance audit
- #114 Audit Settings crash reports and harden settings presentation
- #115 Finish Library interaction polish
- #116 Create a complete app test matrix
- #118 Fix Home recommendation card text overflow
- #123 Improve Search and discovery subscribe flow
- #145 Fix podcast detail episode ordering
- #126 Improve Queue workflows for heavy listeners
- #127 Audit accessibility and Dynamic Type across Tuner UI

### Senior Or Owner-Led Queue

Do not give these to low-thinking agents without a senior wrapper because they
touch release truth, Apple account/signing state, real-device behavior, broad
product judgment, or cross-surface architecture.

- #104 Fix release/build visibility source of truth
- #108 Rebuild recommendations around authored user signal
- #111 Expand Apple platform integrations and OLED polish
- #112 Validate Sign in with Apple and iCloud/CloudKit paths
- #113 Add regression coverage for background playback and silent switch behavior
- #117 Improve release automation after PR merge
- #120 Diagnose Xcode Cloud PrepareBuildForAppStoreConnect failures
- #121 Handle uploaded but unassigned TestFlight builds
- #124 Expand Player feature polish and reliability

### Spec-First Queue

These should become planning/spec PRs or tighter issue contracts before feature
implementation starts.

- #110 Redesign top chrome and safe-area usage
- #119 Add Library power-user features for large collections
- #125 Harden downloads and offline playback

## Immediate Release Lane

### Objective
Get current `main` into TestFlight and make the release surface impossible to
misread again.

### Issues
- #120 Diagnose Xcode Cloud PrepareBuildForAppStoreConnect failures
- #104 Fix release/build visibility source of truth
- #121 Handle uploaded but unassigned TestFlight builds
- #117 Improve release automation after PR merge

### Acceptance
1. Xcode Cloud archives current `main` or a follow-up release commit.
2. The visible internal TestFlight build is newer than build 62.
3. Release tooling reports current repo build, latest uploaded build, latest
   internal-visible build, and latest external-visible build separately.
4. Valid but unassigned builds are treated as release failures, not shipped.

## Performance Lane

### Objective
Make large-library use feel fast with real 250+ show libraries.

### Issues
- #105 Speed up large OPML import for real libraries
- #106 Reduce onboarding subscription latency
- #107 Make Library performant with 250+ subscribed shows

### Acceptance
1. Large OPML import avoids serial bottlenecks where safe and shows accurate
   progress/cancel state.
2. Onboarding can stage three starter subscriptions quickly and hydrate in the
   background.
3. Library scroll, filter, sort, and tab switching remain responsive with 250+
   subscribed shows.
4. Existing debug/perf signposts are used to compare before/after behavior for
   tab switches, Home recommendations, Library load, count loading, and OPML
   stages.

## Recommendation Lane

### Objective
Make recommendations feel authored, local, and trustworthy instead of generic.

### Issues
- #108 Rebuild recommendations around authored user signal
- #118 Fix Home recommendation card text overflow

### Acceptance
1. Explicit feedback and meaningful listening behavior outrank generic recency.
2. Negative feedback visibly changes Home and player suggestions.
3. Recommendation explanations read like OffScript signal, not generic
   algorithm copy.
4. Long recommendation reasons never overflow cards across supported Dynamic
   Type sizes.

## Library Product Lane

### Objective
Turn Library into a power-user surface for large collections.

### Issues
- #115 Finish Library interaction polish
- #119 Add Library power-user features for large collections
- #123 Improve Search and discovery subscribe flow
- #145 Fix podcast detail episode ordering

### Acceptance
1. Alphabet #-Z carousel selection works reliably and jumps to the intended or
   nearest section.
2. Import, search, subscribe, duplicate-feed, and error states are clear.
3. Large-library workflows include useful scopes, metadata signals, and bulk or
   repeated actions where appropriate.
4. Podcast detail episode ordering matches the show/feed chronology expected by
   listeners and does not invert episode-number style feeds.
5. The Library stays visually Tuner-native and performant under real library
   sizes.

## Tuner UI and Accessibility Lane

### Objective
Finish the OLED/Tuner visual system without sacrificing accessibility.

### Issues
- #109 Complete full Tuner UI conformance audit
- #110 Redesign top chrome and safe-area usage
- #111 Expand Apple platform integrations and OLED polish
- #127 Audit accessibility and Dynamic Type across Tuner UI

### Acceptance
1. App-controlled Liquid Glass/system-looking controls are replaced or
   explicitly documented as native exceptions.
2. Top chrome uses screen space better without colliding with Dynamic Island or
   iOS status items.
3. OLED surfaces preserve contrast, battery-conscious black, and Tuner visual
   rhythm.
4. VoiceOver, Dynamic Type, reduced motion, and touch targets pass a full app
   audit.

## Apple Platform Lane

### Objective
Make Apple integrations reliable and product-relevant.

### Issues
- #112 Validate Sign in with Apple and iCloud/CloudKit paths
- #113 Add regression coverage for background playback and silent switch behavior

### Acceptance
1. Sign in with Apple works in supported environments with clear failure copy.
2. CloudKit/signing work remains separate until signing preflight passes.
3. Background playback, lock screen behavior, silent switch behavior, route
   changes, interruptions, and Now Playing controls have regression coverage or
   a repeatable real-device checklist.

## Player, Queue, and Offline Lane

### Objective
Make daily listening workflows durable beyond basic playback.

### Issues
- #124 Expand Player feature polish and reliability
- #125 Harden downloads and offline playback
- #126 Improve Queue workflows for heavy listeners

### Acceptance
1. Player controls, chapters, transcripts/show notes, sleep timer, rates, queue
   actions, lock screen, and remote commands are audited together.
2. Downloads recover from interruption, play offline, and expose retry/cleanup
   state clearly.
3. Queue supports heavy-listener workflows with reliable reorder, play-next,
   remove, clear, and current/next indicators.

## Test and Diagnostics Lane

### Objective
Give humans and agents a repeatable way to verify the app end to end.

### Issues
- #116 Create a complete app test matrix
- #114 Audit Settings crash reports and harden settings presentation

### Acceptance
1. The test matrix covers onboarding, import/export, library, search, queue,
   player, background playback, settings, identity/iCloud, recommendations,
   widgets, and Live Activity.
2. Each flow is classified as automated, simulator manual, or TestFlight/device
   manual.
3. Settings has focused smoke coverage and crash-log follow-up for the build 51
   report.

## Current Open Issue Index

- #104 Fix release/build visibility source of truth
- #105 Speed up large OPML import for real libraries
- #106 Reduce onboarding subscription latency
- #107 Make Library performant with 250+ subscribed shows
- #108 Rebuild recommendations around authored user signal
- #109 Complete full Tuner UI conformance audit
- #110 Redesign top chrome and safe-area usage
- #111 Expand Apple platform integrations and OLED polish
- #112 Validate Sign in with Apple and iCloud/CloudKit paths
- #113 Add regression coverage for background playback and silent switch behavior
- #114 Audit Settings crash reports and harden settings presentation
- #115 Finish Library interaction polish
- #116 Create a complete app test matrix
- #117 Improve release automation after PR merge
- #118 Fix Home recommendation card text overflow
- #119 Add Library power-user features for large collections
- #120 Diagnose Xcode Cloud PrepareBuildForAppStoreConnect failures
- #121 Handle uploaded but unassigned TestFlight builds
- #123 Improve Search and discovery subscribe flow
- #124 Expand Player feature polish and reliability
- #125 Harden downloads and offline playback
- #126 Improve Queue workflows for heavy listeners
- #127 Audit accessibility and Dynamic Type across Tuner UI
- #145 Fix podcast detail episode ordering
