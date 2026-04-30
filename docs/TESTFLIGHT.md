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

Pushes to `main` are handled by Xcode Cloud. The old GitHub Actions TestFlight workflow is disabled at `.github/workflows/testflight.yml.disabled` and kept only as a fallback reference.

The Xcode Cloud workflow:

1. Starts from the `main` branch or matching `v*` tags/releases.
2. Runs Apple's archive/sign/upload action with Apple-managed signing.
3. Uses `ci_scripts/ci_post_clone.sh` to materialize `Config/Secrets.xcconfig` from Xcode Cloud environment variables.
4. Uploads the build to TestFlight through App Store Connect.

Manual probes and starts are available from GitHub Actions via **Xcode Cloud Probe**, or locally through `scripts/app_store_connect.py xcode-cloud {probe,inspect,reconfigure,start-build,build-run}`. The GitHub workflow does not archive or upload app binaries.

## Probe And Local Credentials

Required GitHub repository secrets for `.github/workflows/xcode-cloud-probe.yml`:

- `ASC_KEY_ID`: App Store Connect API key ID.
- `ASC_ISSUER_ID`: App Store Connect issuer ID.
- `ASC_KEY_P8_BASE64`: base64-encoded contents of the `.p8` private key.

Xcode Cloud signing/upload credentials are managed by Xcode Cloud and App Store Connect, not by this GitHub workflow. The probe workflow and local `scripts/app_store_connect.py` commands use the API key only to inspect or start Xcode Cloud runs.

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
scripts/app_store_connect.py signing-preflight --profile-type IOS_APP_STORE
scripts/app_store_connect.py status --limit 8
scripts/app_store_connect.py sync-latest
scripts/app_store_connect.py wait-build --build 2026042501 --require-valid
scripts/app_store_connect.py set-beta-notes --build 2026042501 --notes-file build/TestFlight/notes/testflight-notes.txt
```

`sync-latest` is dry-run by default. Use `scripts/app_store_connect.py sync-latest --apply` only when the latest eligible build is missing beta-group access and should be made available to all beta groups.

`signing-preflight` decodes every active matching App Store provisioning profile from App Store Connect and verifies each profile contains the CloudKit container passed via `--cloudkit-container`, or the default `iCloud.<bundle-id>` when that flag is omitted. Run it before any manual TestFlight upload and after changing iCloud/App ID settings.

## CloudKit Signing Repair

If `signing-preflight` reports that the active `IOS_APP_STORE` profile is missing `iCloud.com.offscript.app`, fix the App ID/profile in Apple Developer before rerunning Xcode Cloud:

1. Open Apple Developer → Certificates, Identifiers & Profiles → Identifiers → App IDs → `com.offscript.app`.
2. Enable iCloud, select CloudKit support, and attach the `iCloud.com.offscript.app` iCloud container.
3. Regenerate the App Store Connect provisioning profile for `com.offscript.app`.
4. Rerun `scripts/app_store_connect.py signing-preflight --profile-type IOS_APP_STORE`.
5. Rerun the Xcode Cloud build only after the preflight prints `OK`.

Apple documents that iCloud requires at least one iCloud container, that creating/managing iCloud containers requires Account Holder or Admin access, and that changing App ID capabilities requires provisioning profile updates:

- https://developer.apple.com/help/account/identifiers/create-an-icloud-container/
- https://developer.apple.com/help/account/identifiers/enable-app-capabilities/
- https://developer.apple.com/help/account/provisioning-profiles/edit-download-or-delete-profiles/

## Current App Store Connect Convention

- Bundle ID: `com.offscript.app`
- Team ID: `363TRR79UG`
- App Store name: `Offscript: A Podcast App`
- Home screen display name: `OffScript`
