<!-- For external contributors: please open an issue first to discuss the change. See CONTRIBUTING.md. -->

## Summary

<!-- 1-3 bullets. What changes, why now. -->
-
-

## Test plan

<!-- Markdown checklist. Stuff a reviewer should verify before merging. -->
- [ ] `xcodebuild` clean build succeeds locally
- [ ] Unit tests pass: `xcodebuild test -project OffScript.xcodeproj -scheme OffScript -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro'`
- [ ] Manually verified on simulator (note device + iOS version):
- [ ] No new inline `Color.white.opacity(...)` or raw `Font.system(...)` — used named tokens
- [ ] No bare `try?` — all errors logged via `OSLog`
- [ ] If touching SwiftData: predicate-filtered `FetchDescriptor`, no `persistentModelID` in `#Predicate`

## Screenshots / recordings

<!-- For UI changes — drag-drop into the textarea. -->

## Risk

<!-- One line. -->
- **Affected surfaces:**
- **Rollback path:** revert this PR, push to `main`, CI auto-deploys the prior build.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
