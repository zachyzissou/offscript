#!/bin/sh
# Xcode Cloud runs this script immediately after cloning the repo, before
# any xcodebuild step. We use it to materialize the gitignored
# Config/Secrets.xcconfig from the Xcode Cloud "Environment Variables"
# panel so the project's base configuration reference resolves.
#
# Set $SENTRY_DSN as an Xcode Cloud secret (Workflows → Environment →
# Environment Variables → "Add Variable" → check "Secret"). Without it,
# CrashReporter.configure() detects the empty DSN and silently skips
# Sentry init — builds still ship, they just don't send crash reports.
#
# Path note: Xcode Cloud sets CI_WORKSPACE to the repo root, so we
# resolve config paths relative to that.

set -eu

if [ -z "${CI_WORKSPACE:-}" ]; then
  echo "ci_post_clone: CI_WORKSPACE is unset — bailing"
  exit 1
fi

cd "$CI_WORKSPACE"

mkdir -p Config
umask 077

if [ -n "${SENTRY_DSN:-}" ]; then
  printf 'SENTRY_DSN = %s\n' "$SENTRY_DSN" > Config/Secrets.xcconfig
  echo "ci_post_clone: wrote SENTRY_DSN into Config/Secrets.xcconfig"
else
  printf 'SENTRY_DSN =\n' > Config/Secrets.xcconfig
  echo "ci_post_clone: SENTRY_DSN not set — Sentry will be disabled in this build"
fi
