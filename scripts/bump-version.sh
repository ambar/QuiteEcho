#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: bump-version.sh <version> (e.g. 1.0.0)}"

# Validate semver format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be semver (e.g. 1.0.0)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1. Info.plist — CFBundleVersion and CFBundleShortVersionString
sed -E -i '' \
  '/<key>CFBundle(Short)?Version(String)?<\/key>/{n;s|<string>[^<]*</string>|<string>'"$VERSION"'</string>|;}' \
  "$ROOT/Resources/Info.plist"

echo "Version bumped to $VERSION"
grep -n "$VERSION" "$ROOT/Resources/Info.plist"
