#!/bin/sh
# Xcode Cloud runs this script immediately after cloning the repo. We use
# it to materialize the gitignored Config/Secrets.xcconfig from the Xcode
# Cloud "Environment Variables" panel so the project's base configuration
# reference resolves.
#
# Set $SENTRY_DSN as an Xcode Cloud secret (Workflows → Environment →
# Environment Variables → "Add Variable" → check "Secret"). Without it,
# CrashReporter.configure() detects the empty DSN and silently skips
# Sentry init — builds still ship, they just don't send crash reports.
#
# Working-directory contract: Apple runs ci_scripts/* with PWD == ci_scripts/.
# Resolution priority for the repo root:
#   1. $CI_PRIMARY_REPOSITORY_PATH (newer Xcode Cloud env)
#   2. $CI_WORKSPACE                (older / current-default env)
#   3. $(dirname "$0")/..           (filesystem fallback — works because
#                                    Apple guarantees the script lives in
#                                    ci_scripts/ which is one level under
#                                    the repo root)
#
# Anything in this script must succeed unconditionally. A non-zero exit
# fails the entire build action — see Apple's docs on ci_post_clone:
# https://developer.apple.com/documentation/xcode/writing-custom-build-scripts

set -eu

if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  REPO_ROOT="$CI_PRIMARY_REPOSITORY_PATH"
elif [ -n "${CI_WORKSPACE:-}" ]; then
  REPO_ROOT="$CI_WORKSPACE"
else
  # Apple runs us from ci_scripts/ regardless of platform.
  REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

cd "$REPO_ROOT"
echo "ci_post_clone: REPO_ROOT=$REPO_ROOT"

mkdir -p Config
umask 077

if [ -n "${SENTRY_DSN:-}" ]; then
  printf 'SENTRY_DSN = %s\n' "$SENTRY_DSN" > Config/Secrets.xcconfig
  echo "ci_post_clone: wrote SENTRY_DSN into Config/Secrets.xcconfig"
else
  printf 'SENTRY_DSN =\n' > Config/Secrets.xcconfig
  echo "ci_post_clone: SENTRY_DSN not set — Sentry will be disabled in this build"
fi
