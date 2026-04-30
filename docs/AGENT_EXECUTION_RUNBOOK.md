# OffScript Agent Execution Runbook

Use this when launching a low-thinking implementation agent against the
OffScript roadmap. The goal is a narrow, reviewable PR, not broad exploration.

## Source Of Truth

1. GitHub Project `OffScript` is the live kanban.
2. `docs/NEXT_IMPLEMENTATION_BACKLOG.md` groups the open issues into product
   lanes.
3. `CHANGELOG.md` uses an `Unreleased` section for agent-visible product,
   performance, release, and diagnostics work. Do not create versioned
   changelog blocks in feature PRs; versioned blocks belong with the version
   bump/release PR described in `CONTRIBUTING.md`.
4. PR #38 CloudKit signing remains separate. Do not merge or fold it into other
   work unless its signing preflight passes.

## Issue Readiness Contract

An issue is ready for low-thinking implementation only if it has:

1. a concrete problem statement;
2. acceptance criteria that can be checked locally or in TestFlight;
3. expected code areas or workflows;
4. explicit non-goals or risks when Apple signing, CloudKit, identity, audio,
   or release automation is involved;
5. a verification command or manual checklist.

If any of those are missing, first create a planning/docs PR or add an issue
comment that turns the issue into an executable spec.

## Kanban Routing Labels

Use the project status and agent labels together. Status alone is not enough.

- `agent:low-thinking-ready`: safe for a constrained implementation agent when
  this runbook and the issue contract are followed.
- `agent:needs-spec`: do not implement yet. First tighten acceptance criteria,
  split the first slice, or add missing verification/non-goals.
- `agent:senior-required`: do not assign to a low-thinking agent. These issues
  need owner action, release/signing authority, real-device validation,
  cross-surface product judgment, or broad architecture work.

Label prefilter for low-thinking candidates:

```sh
gh issue list \
  --state open \
  --label "agent:low-thinking-ready" \
  --search '-label:"agent:senior-required"'
```

Before launching the agent, confirm the issue is `Ready` in the OffScript
project. Backlog issues with `agent:low-thinking-ready` are valid only when a
senior/controller agent first selects a narrow slice from the issue contract.

## Branch And PR Workflow

```sh
git fetch origin main
git switch -c codex/<short-issue-slug> origin/main
```

Rules:

1. Keep the branch scoped to one issue or one tightly coupled PR.
2. Prefer existing app patterns over new architecture.
3. Preserve the Tuner/OLED UI language unless the surface is Apple-native by
   requirement.
4. Do not hide failures behind disabled tests.
5. Run the narrowest meaningful test first, then the full OffScript unit suite
   before PR.
6. Open a PR with issue number, summary, verification, and changelog note.
7. Let Copilot review the PR, address every actionable comment, and rerun
   tests.
8. Low-thinking agents stop at PR-ready. A senior/controller agent owns merge
   authority because merging to `main` triggers Xcode Cloud/TestFlight and must
   account for release state.

## Standard Verification

Primary unit gate:

```sh
xcodebuild test \
  -project OffScript.xcodeproj \
  -scheme OffScript \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro' \
  -only-testing:OffScriptTests \
  CODE_SIGNING_ALLOWED=NO
```

Use focused UI tests when touching Library navigation, Settings, onboarding,
or large-library behavior. Use real-device/TestFlight checklists for background
audio, lock screen, silent switch, Sign in with Apple, iCloud/CloudKit, and
release visibility.

## Recommended Next Issues

These are not the only runnable issues. They are the safest starting points for
low-thinking implementation agents because the code areas, guardrails, and
verification path are constrained.

### #105 Speed Up Large OPML Import

Best for performance agents. Start in:

- `OffScript/BatchImportService.swift`
- `OffScript/PodcastServices.swift`
- `OffScript/LibraryImportSheet.swift`
- `OffScriptTests/OffScriptTests.swift`

Required proof:

- large import planning/staging test or benchmark;
- no regression to dedupe, cancellation, retry, or bootstrap-cap tests;
- changelog entry under Library performance or import/sync.

Non-goals:

- do not make SwiftData `ModelContext` mutations from arbitrary background
  tasks;
- do not remove cancellation or retryable failure state.

### #107 Make Library Performant With 250+ Shows

Best for UI/perf agents. Start in:

- `OffScript/LibraryView.swift`
- `OffScript/ContentView.swift`
- `OffScriptTests/OffScriptTests.swift`
- existing performance signposts in `OffScriptPerformanceLog`

Required proof:

- deterministic 250+ show seed path or UI smoke where practical;
- no row/card text overflow;
- no hidden tab retaining expensive active work;
- changelog entry under Library performance.

Non-goals:

- do not reintroduce live `@Query` directory arrays at the root Library level;
- do not replace the Tuner alphabet carousel with a default picker.

### #109 Complete Tuner UI Conformance Audit

Best for UI agents. Start with a read-only scan, then patch one surface group.

Required proof:

- list every intentionally native exception;
- screenshots or UI tests for representative surfaces;
- changelog entry naming completed surfaces.

Non-goals:

- do not replace Apple-required Sign in with Apple controls;
- do not use default Liquid Glass for app-authored controls.

## Release And Cloud Notes

Xcode Cloud `PrepareBuildForAppStoreConnect` failures have repeatedly been a
workflow/App Store Connect preparation problem, not necessarily a code archive
problem. Before changing code for that class of failure, inspect the build run
with:

```sh
scripts/app_store_connect.py xcode-cloud build-run <build-run-id>
```

If Archive fails with `PrepareBuildForAppStoreConnect` and TestFlight is
skipped, confirm the Xcode Cloud workflow distribution audience and deployment
preparation settings before bumping versions or editing unrelated code.
