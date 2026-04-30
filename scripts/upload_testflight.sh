#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/OffScript.xcodeproj"
SCHEME="OffScript"
CONFIGURATION="Release"
ARCHIVE_PATH="$ROOT_DIR/build/TestFlight/OffScript.xcarchive"
EXPORT_PATH="$ROOT_DIR/build/TestFlight/Upload"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-$ROOT_DIR/Config/TestFlightUploadOptions.plist}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
VALIDATE_ONLY="false"
ASC_SCRIPT="$ROOT_DIR/scripts/app_store_connect.py"
BUILD_NUMBER="${BUILD_NUMBER:-}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-363TRR79UG}"
ENV_FILES=(
	"$ROOT_DIR/.env.appstoreconnect"
	"$ROOT_DIR/Config/.env.appstoreconnect"
	"$ROOT_DIR/Config/AppStoreConnect.local.env"
)

if [[ "${1:-}" == "--validate-only" ]]; then
	VALIDATE_ONLY="true"
fi

fail() {
	echo "error: $*" >&2
	exit 1
}

load_env_files() {
	local env_file
	for env_file in "${ENV_FILES[@]}"; do
		if [[ -f "$env_file" ]]; then
			set -a
			# shellcheck disable=SC1090
			source "$env_file"
			set +a
		fi
	done
}

plist_value() {
	"$PLIST_BUDDY" -c "Print :$1" "$2" 2>/dev/null || true
}

require_external_capable_options() {
	[[ -f "$EXPORT_OPTIONS" ]] || fail "missing export options: $EXPORT_OPTIONS"

	local destination method internal_only
	destination="$(plist_value destination "$EXPORT_OPTIONS")"
	method="$(plist_value method "$EXPORT_OPTIONS")"
	internal_only="$(plist_value testFlightInternalTestingOnly "$EXPORT_OPTIONS")"

	[[ "$destination" == "upload" ]] || fail "export options must use destination=upload"
	[[ "$method" == "app-store-connect" ]] || fail "export options must use method=app-store-connect"
	[[ "$internal_only" != "true" && "$internal_only" != "YES" ]] || fail "refusing internal-only TestFlight upload options"
}

archive_metadata() {
	local archive_info="$ARCHIVE_PATH/Info.plist"
	[[ -f "$archive_info" ]] || fail "archive metadata not found: $archive_info"

	local version build bundle_id team
	version="$(plist_value ApplicationProperties:CFBundleShortVersionString "$archive_info")"
	build="$(plist_value ApplicationProperties:CFBundleVersion "$archive_info")"
	bundle_id="$(plist_value ApplicationProperties:CFBundleIdentifier "$archive_info")"
	team="$(plist_value ApplicationProperties:Team "$archive_info")"

	echo "Archive: $bundle_id $version ($build), team $team"
}

check_build_number_available() {
	if [[ -n "${ASC_KEY_PATH:-}" ]]; then
		local args=(build-exists)
		[[ -z "$MARKETING_VERSION" ]] || args+=(--version "$MARKETING_VERSION")
		[[ -z "$BUILD_NUMBER" ]] || args+=(--build "$BUILD_NUMBER")
		"$ASC_SCRIPT" "${args[@]}"
	else
		echo "warning: skipping App Store Connect duplicate-build preflight; ASC_KEY_PATH is not set" >&2
	fi
}

check_cloudkit_signing_ready() {
	if ! "$PLIST_BUDDY" -c "Print :com.apple.developer.icloud-container-identifiers:0" "$ROOT_DIR/OffScript/OffScript.entitlements" >/dev/null 2>&1; then
		return
	fi

	if [[ -n "${ASC_KEY_PATH:-}" ]]; then
		"$ASC_SCRIPT" signing-preflight --profile-type IOS_APP_STORE
	else
		echo "warning: skipping CloudKit signing preflight; ASC_KEY_PATH is not set" >&2
	fi
}

prepare_xcode_args() {
	BUILD_SETTINGS=()
	XCODE_AUTH_ARGS=()

	[[ -z "$MARKETING_VERSION" ]] || BUILD_SETTINGS+=("MARKETING_VERSION=$MARKETING_VERSION")
	[[ -z "$BUILD_NUMBER" ]] || BUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
	[[ -z "$DEVELOPMENT_TEAM" ]] || BUILD_SETTINGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" "CODE_SIGN_STYLE=Automatic")

	if [[ -n "${ASC_KEY_PATH:-}" ]]; then
		[[ -n "${ASC_KEY_ID:-}" ]] || fail "ASC_KEY_ID is required when ASC_KEY_PATH is set"
		if [[ -z "${ASC_ISSUER_ID:-}" ]]; then
			if [[ "${CI:-false}" == "true" ]]; then
				fail "ASC_ISSUER_ID is required for CI xcodebuild signing/upload authentication"
			fi
			echo "warning: ASC_KEY_PATH set without ASC_ISSUER_ID; xcodebuild will use the local Xcode account instead" >&2
		else
			XCODE_AUTH_ARGS+=(
				-authenticationKeyPath "$ASC_KEY_PATH"
				-authenticationKeyID "$ASC_KEY_ID"
				-authenticationKeyIssuerID "$ASC_ISSUER_ID"
			)
		fi
	fi
}

load_env_files
require_external_capable_options

if [[ "$VALIDATE_ONLY" == "true" ]]; then
	echo "Export options are external-capable: $EXPORT_OPTIONS"
	exit 0
fi

check_build_number_available
check_cloudkit_signing_ready

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

prepare_xcode_args

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild \
	-project "$PROJECT_PATH" \
	-scheme "$SCHEME" \
	-configuration "$CONFIGURATION" \
	-destination "generic/platform=iOS" \
	-archivePath "$ARCHIVE_PATH" \
	"${BUILD_SETTINGS[@]}" \
	archive \
	-allowProvisioningUpdates \
	"${XCODE_AUTH_ARGS[@]}"

archive_metadata

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild \
	-exportArchive \
	-archivePath "$ARCHIVE_PATH" \
	-exportPath "$EXPORT_PATH" \
	-exportOptionsPlist "$EXPORT_OPTIONS" \
	-allowProvisioningUpdates \
	"${XCODE_AUTH_ARGS[@]}"
