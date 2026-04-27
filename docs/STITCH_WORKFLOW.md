# OffScript Stitch Workflow

Use Stitch as a visual exploration tool for the next design direction. The source of truth for vNext design decisions is the repo-level `DESIGN.md`.

Important distinction:

- `DESIGN.md` describes the target design direction.
- `CLAUDE.md`, `docs/UI_REDESIGN.md`, and `OffScript/AppTheme.swift` describe current implementation constraints and migration rules.
- Do not force Stitch to match today's UI defects or current token limitations. Use Stitch to define the destination, then update SwiftUI tokens and components to catch up.

## Stitch Project

- Project title: `OffScript iPhone Design System`
- Project ID: `10602978267448639151`
- Project resource: `projects/10602978267448639151`
- Design system asset: `assets/9613635482825796653`
- Design system name: `OffScript vNext - The Signal Desk`

Generated concept screens:

- `Home - The Signal Desk`
- Screen ID: `3aacd410dcb74e4997fd578013f8005d`
- Screen resource: `projects/10602978267448639151/screens/3aacd410dcb74e4997fd578013f8005d`
- Generation session: `8277637935998683575`
- `Home: Editorial Brief`
- Screen ID: `d50c92dda71c4da28d17f5fce60c1023`
- Screen resource: `projects/10602978267448639151/screens/d50c92dda71c4da28d17f5fce60c1023`
- Local screenshot: `docs/stitch/screens/home-a-editorial-brief.png`
- `Home: Signal Console`
- Screen ID: `3171473cdca84ad2929ddac67c912b4c`
- Screen resource: `projects/10602978267448639151/screens/3171473cdca84ad2929ddac67c912b4c`
- Local screenshot: `docs/stitch/screens/home-b-signal-console.png`
- `Home: Immersive Room`
- Screen ID: `054045e1fe7d4192a159173cd630bb26`
- Screen resource: `projects/10602978267448639151/screens/054045e1fe7d4192a159173cd630bb26`
- Local screenshot: `docs/stitch/screens/home-c-immersive-room.png`
- `Home: Signal Observatory`
- Screen ID: `65bd2773d81249ad8d43b1ea8f368fc8`
- Screen resource: `projects/10602978267448639151/screens/65bd2773d81249ad8d43b1ea8f368fc8`
- Local screenshot: `docs/stitch/screens/home-d0-signal-observatory.png`
- `Home: Signal Mixer`
- Screen ID: `15752ba9545a48c7bbab5ecfcccc6bc9`
- Screen resource: `projects/10602978267448639151/screens/15752ba9545a48c7bbab5ecfcccc6bc9`
- Local screenshot: `docs/stitch/screens/home-d1-signal-mixer.png`
- `Home: Signal Observatory` variant, `Physical Analog Studio`
- Screen ID: `963e9d77c6144a58a7a89744e3c2e06f`
- Screen resource: `projects/10602978267448639151/screens/963e9d77c6144a58a7a89744e3c2e06f`
- Local screenshot: `docs/stitch/screens/home-d2-analog-studio.png`
- `Home: Signal Observatory` variant, `Brutalist Editorial`
- Screen ID: `b83d29436bc84b1f95c213b8da87186f`
- Screen resource: `projects/10602978267448639151/screens/b83d29436bc84b1f95c213b8da87186f`
- Local screenshot: `docs/stitch/screens/home-d3-brutalist-editorial.png`
- `Home: Signal Observatory` variant, `Topographic Signal Map`
- Screen ID: `ef3c6e8371ec41198d6097cb5b22f4af`
- Screen resource: `projects/10602978267448639151/screens/ef3c6e8371ec41198d6097cb5b22f4af`
- Local screenshot: `docs/stitch/screens/home-d4-topographic-signal-map.png`
- `Home: Signal Observatory` variant, `Analog Master Console`
- Screen ID: `e7b6c0068aeb4367b57b6132c1d225c6`
- Screen resource: `projects/10602978267448639151/screens/e7b6c0068aeb4367b57b6132c1d225c6`
- Local screenshot: `docs/stitch/screens/home-e1-analog-master-console.png`
- `Home: Signal Observatory` variant, `Topographic Recommendation Map`
- Screen ID: `b14d9af80b2c4e1e9d5fbf0a76ae85ef`
- Screen resource: `projects/10602978267448639151/screens/b14d9af80b2c4e1e9d5fbf0a76ae85ef`
- Local screenshot: `docs/stitch/screens/home-e2-topographic-recommendation-map.png`
- `Home: Signal Observatory` variant, `Editorial Zine`
- Screen ID: `f87bd089b7b84625b6477c9a834273e5`
- Screen resource: `projects/10602978267448639151/screens/f87bd089b7b84625b6477c9a834273e5`
- Local screenshot: `docs/stitch/screens/home-e3-editorial-zine.png`
- `Home: Signal Observatory` variant, `Audio-Instrument Cockpit`
- Screen ID: `3645bd68ab8449aa8b7b0cb2da34d598`
- Screen resource: `projects/10602978267448639151/screens/3645bd68ab8449aa8b7b0cb2da34d598`
- Local screenshot: `docs/stitch/screens/home-e4-audio-instrument-cockpit.png`
- `Home: Signal Observatory` variant, `Premium Listening Room`
- Screen ID: `3d0aa9279c39443280de4bb80b0cad3e`
- Screen resource: `projects/10602978267448639151/screens/3d0aa9279c39443280de4bb80b0cad3e`
- Local screenshot: `docs/stitch/screens/home-e5-premium-listening-room.png`

## Stitch MCP Payload Note

The Stitch MCP design-system tools require a structured object even though some tool descriptions make `designSystem` look like a plain string.

Working shape:

```json
{
  "projectId": "10602978267448639151",
  "designSystem": {
    "displayName": "OffScript vNext - The Signal Desk",
    "theme": {
      "colorMode": "DARK",
      "headlineFont": "NEWSREADER",
      "bodyFont": "INTER",
      "labelFont": "SPACE_GROTESK",
      "roundness": "ROUND_TWELVE",
      "customColor": "#FF7A1A",
      "colorVariant": "VIBRANT",
      "overridePrimaryColor": "#FF7A1A",
      "overrideSecondaryColor": "#E9CFA6",
      "overrideTertiaryColor": "#B7FF6A",
      "overrideNeutralColor": "#101113",
      "designMd": "..."
    }
  }
}
```

Use `list_design_systems` to verify the asset. `get_project` may still show an empty design theme even after the design system asset is created.

## Stitch Variant Payload Note

The exposed Codex MCP schema currently describes `variantOptions` as a string, but the Stitch MCP API expects an object. Passing a natural-language string returns `Request contains an invalid argument.`

Working shape:

```json
{
  "projectId": "10602978267448639151",
  "selectedScreenIds": ["65bd2773d81249ad8d43b1ea8f368fc8"],
  "prompt": "Create three bolder alternatives...",
  "variantOptions": {
    "variantCount": 3,
    "creativeRange": "REIMAGINE",
    "aspects": [
      "LAYOUT",
      "COLOR_SCHEME",
      "IMAGES",
      "TEXT_FONT",
      "TEXT_CONTENT"
    ]
  },
  "deviceType": "MOBILE",
  "modelId": "GEMINI_3_1_PRO"
}
```

Known values from the Stitch docs and client bundle:

- `variantCount`: `1` through `5`.
- `creativeRange`: `REFINE`, `EXPLORE`, or `REIMAGINE`.
- `aspects`: `LAYOUT`, `COLOR_SCHEME`, `IMAGES`, `TEXT_FONT`, `TEXT_CONTENT`.
- The public SDK docs list `GEMINI_3_PRO` and `GEMINI_3_FLASH`; the live Codex MCP schema also exposes `GEMINI_3_1_PRO`, which worked for high-quality visual exploration.
- There is no documented MCP/API `thinking` boolean in the current callable surface. Product/UI references to Thinking mode are not the same as a stable tool parameter.

## Current Local MCP Status

Gemini/Antigravity config was checked at:

- `/Users/zachgonser/.gemini/antigravity/mcp_config.json`
- `/Users/zachgonser/.gemini/settings.json`

Both currently define only `unityMCP`. No Stitch MCP server config was found in the local Gemini, Cursor, Copilot, Kiro, Windsurf, or LM Studio MCP config files.

Codex has been configured globally with the Stitch remote MCP endpoint:

```toml
[mcp_servers.stitch]
url = "https://stitch.googleapis.com/mcp"
env_http_headers = { "X-Goog-Api-Key" = "STITCH_API_KEY" }
```

The key itself must stay outside the repository and outside checked-in config. Set it locally as `STITCH_API_KEY`.

For terminal-launched Codex sessions:

```sh
export STITCH_API_KEY="..."
```

For the macOS desktop app, set it through launch services, then fully restart Codex:

```sh
launchctl setenv STITCH_API_KEY "..."
```

Do not commit local OAuth files, API keys, tokens, account files, or generated private config to this repository.

## Stitch Prompt Contract

When creating or refining OffScript screens in Stitch, attach or paste `DESIGN.md` and use this framing:

```text
Use the attached OffScript vNext DESIGN.md as the source of truth. Design an iPhone podcast app screen for a recommendation-first audio app called OffScript. The style is The Signal Desk: dark editorial listening room, graphite physical surfaces, warm paper typography, mono signal labels, orange playback actions, cream recommendation notes, artwork-led color, tactile waveform details, and iOS-native bottom navigation. Make recommendations explainable and human. Avoid generic podcast app layouts, purple SaaS gradients, heavy glass over artwork, default List chrome, and equal-weight card feeds.
```

## What To Generate First

Prioritize screens where visual hierarchy and layout correctness matter most:

1. Home with one dominant `Best Next` recommendation, supporting rails, and visible recommendation reasons.
2. Mini player docked above the tab bar with no overlap and an integrated progress bar.
3. Full player with fit-scaled artwork, foreground transport controls, and visible queue context.
4. Library as active collections: `In Progress`, `Fresh Episodes`, `Downloaded`, and `Shows`.
5. Search/import flow with topic-led discovery and clear post-import payoff.

## Implementation Rules For Stitch Output

- Treat Stitch output as direction, not production code.
- Translate colors into vNext `Color.offscript...` tokens. Add new tokens when current ones are insufficient.
- Translate type into vNext `Font.offscript...` tokens. Add new named roles when current ones are insufficient.
- Translate spacing into `OffScriptTheme` spacing constants.
- Clip all artwork explicitly; no image may escape its card bounds.
- Preserve the bottom tab architecture.
- Add or update shared SwiftUI components when a pattern repeats.
- If Stitch suggests a new reusable token, add it to `OffScript/AppTheme.swift` and update `DESIGN.md`.

## Visual QA Checklist

Before implementing a Stitch-inspired screen, verify:

- Recommendation reasons are visible and human-readable.
- The primary action is obvious.
- The mini player does not overlap tab labels or icons.
- Full-player artwork is not zoom-cropped by default.
- Artwork never bleeds into neighboring cards.
- Cards have enough vertical and horizontal breathing room.
- Text remains legible on real podcast artwork and dark backgrounds.
- Loading, empty, offline, and error states use the same visual language.

## SwiftUI Design Variant Harness

The app includes a DEBUG-only Home variant switch so Stitch directions can be evaluated in the simulator with the same seeded podcast data:

- `hero`: spacious E5 monolith direction.
- `feed`: compact shortlist direction.
- `split`: balanced lead pick plus ranked signals.

Use this with the debug seed/playback args:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl launch --terminate-running-process booted com.offscript.app \
  -offscript.hasSeenOnboarding YES \
  -offscript.debugSeedLibrary YES \
  -offscript.debugBootPlayback YES \
  -offscript.debugLaunchTab 0 \
  -offscript.debugHomeVariant feed
```

Capture the result:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun simctl io booted screenshot docs/stitch/screens/current-home-feed.png
```

Or rebuild, install, launch, and capture all three local Home variants:

```sh
scripts/capture_home_variants.sh
```

Keep this harness DEBUG-only until there is a real telemetry-backed beta experiment. The first production beta should use one coherent Home direction, not expose three layouts to testers.
