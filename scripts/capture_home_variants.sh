#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-booted}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 17,OS=26.4.1}"
OUT_DIR="$ROOT_DIR/docs/stitch/screens"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

mkdir -p "$OUT_DIR"

xcodebuild \
  -project "$ROOT_DIR/OffScript.xcodeproj" \
  -scheme OffScript \
  -destination "$DESTINATION" \
  build

build_settings="$(mktemp)"
trap 'rm -f "$build_settings"' EXIT

xcodebuild \
  -project "$ROOT_DIR/OffScript.xcodeproj" \
  -scheme OffScript \
  -destination "$DESTINATION" \
  -showBuildSettings > "$build_settings"

built_products_dir="$(awk -F' = ' '/ BUILT_PRODUCTS_DIR = / { print $2; exit }' "$build_settings")"
full_product_name="$(awk -F' = ' '/ FULL_PRODUCT_NAME = / { print $2; exit }' "$build_settings")"
app_path="$built_products_dir/$full_product_name"

xcrun simctl install "$DEVICE" "$app_path"

for variant in hero feed split; do
  xcrun simctl launch --terminate-running-process "$DEVICE" com.offscript.app \
    -offscript.hasSeenOnboarding YES \
    -offscript.debugSeedLibrary YES \
    -offscript.debugLaunchTab 0 \
    -offscript.debugHomeVariant "$variant" \
    -offscript.debugBootPlayback YES

  sleep 2

  xcrun simctl io "$DEVICE" screenshot "$OUT_DIR/current-home-$variant.png"
done

