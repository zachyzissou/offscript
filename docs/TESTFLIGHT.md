# TestFlight Release Policy

## Internal And External Sync

OffScript uses the same uploaded build for internal and external TestFlight whenever a build is intended for beta testing. Do not upload beta candidates as `TestFlight Internal Only`; those builds cannot be added to external tester groups later.

Internal-only builds are allowed only for throwaway signing/debug checks. If a build may go to external testers, upload it with `Config/TestFlightUploadOptions.plist`.

## Upload A Beta Candidate

1. Bump `MARKETING_VERSION` only when the user-facing beta version changes.
2. Bump `CURRENT_PROJECT_VERSION` for every App Store Connect upload.
3. Run `scripts/upload_testflight.sh`.
4. In App Store Connect, add the same processed build to the internal group and the external group.
5. Before inviting testers, verify both groups show the same version and build number.

The upload script refuses options files that include `testFlightInternalTestingOnly = true`.

## Automated Main Branch Uploads

Pushes to `main` run `.github/workflows/testflight.yml`.

The workflow:

1. Computes a unique build number from the UTC date, GitHub run number, and run attempt.
2. Generates `CHANGELOG.md`, `WHAT_TO_TEST.md`, and `testflight-notes.txt` under `build/TestFlight/notes`.
3. Runs the iOS test suite on an available iPhone simulator.
4. Archives and uploads the Release build with `scripts/upload_testflight.sh`.
5. Waits for App Store Connect processing, writes the generated notes into TestFlight's build localization, and syncs the latest eligible build to all beta groups.
6. Uploads the changelog, What to Test notes, TestFlight notes, App Store Connect status snapshot, and test result bundle as GitHub Actions artifacts.

Manual runs are available from GitHub Actions via **TestFlight Beta**. Use the manual inputs when a build needs custom release wording:

- `marketing_version`: override `MARKETING_VERSION`.
- `build_number`: override `CURRENT_PROJECT_VERSION`.
- `summary`: short changelog summary.
- `what_to_test`: extra tester instructions appended to generated What to Test notes.

## GitHub Secrets

Required repository secrets:

- `ASC_KEY_ID`: App Store Connect API key ID.
- `ASC_ISSUER_ID`: App Store Connect issuer ID.
- `ASC_KEY_P8_BASE64`: base64-encoded contents of the `.p8` private key.

The GitHub workflow expects a **team** App Store Connect API key because `xcodebuild -allowProvisioningUpdates` requires `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID` for CI signing/upload authentication. Individual API keys can still be used by `scripts/app_store_connect.py` for local status checks, but they do not satisfy the CI `xcodebuild` issuer-ID requirement.

Create the base64 secret locally with:

```bash
base64 -i /path/to/AuthKey_XXXXXXXXXX.p8 | pbcopy
```

## App Store Connect API Status Checks

Use `scripts/app_store_connect.py status` to inspect the App Store Connect app record, beta groups, recent builds, and beta build states.

Local credentials live in `.env.appstoreconnect` or `Config/AppStoreConnect.local.env`; both are ignored by git. Team API keys require `ASC_ISSUER_ID`. Individual API keys should set `ASC_KEY_TYPE=individual` and do not use an issuer ID.

Useful checks:

```bash
scripts/app_store_connect.py doctor
scripts/app_store_connect.py status --limit 8
scripts/app_store_connect.py sync-latest
scripts/app_store_connect.py wait-build --build 2026042501 --require-valid
scripts/app_store_connect.py set-beta-notes --build 2026042501 --notes-file build/TestFlight/notes/testflight-notes.txt
```

`sync-latest` is dry-run by default. Use `scripts/app_store_connect.py sync-latest --apply` only when the latest eligible build is missing beta-group access and should be made available to all beta groups.

## Current App Store Connect Convention

- Bundle ID: `com.offscript.app`
- Team ID: `363TRR79UG`
- App Store name: `Offscript: A Podcast App`
- Home screen display name: `OffScript`
