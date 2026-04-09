#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: bump-version.sh <version> (e.g. 1.0.0 or 1.0.0-beta.1)}"

# Accept release versions plus beta prereleases only.
if [[ ! "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-beta\.([0-9]+))?$ ]]; then
  echo "Error: version must be x.y.z or x.y.z-beta.N" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"

# CFBundleShortVersionString = marketing version (e.g. 0.2.5-beta.1)
# CFBundleVersion = monotonically increasing global build number.
# To migrate from the previous dotted scheme (e.g. 0.2.5001), strip dots once
# and continue incrementing from that integer.
CURRENT_BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
if [[ "$CURRENT_BUILD_VERSION" =~ ^[0-9]+$ ]]; then
  CURRENT_BUILD_NUMBER="$CURRENT_BUILD_VERSION"
elif [[ "$CURRENT_BUILD_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  CURRENT_BUILD_NUMBER="${CURRENT_BUILD_VERSION//./}"
else
  echo "Error: unsupported CFBundleVersion format: $CURRENT_BUILD_VERSION" >&2
  exit 1
fi

BUILD_VERSION=$((10#$CURRENT_BUILD_NUMBER + 1))

sed -E -i '' \
  '/<key>CFBundleShortVersionString<\/key>/{n;s|<string>[^<]*</string>|<string>'"$VERSION"'</string>|;}' \
  "$PLIST"

sed -E -i '' \
  '/<key>CFBundleVersion<\/key>/{n;s|<string>[^<]*</string>|<string>'"$BUILD_VERSION"'</string>|;}' \
  "$PLIST"

echo "CFBundleShortVersionString = $VERSION"
echo "CFBundleVersion            = $BUILD_VERSION"
