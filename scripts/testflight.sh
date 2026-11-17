#!/usr/bin/env bash
# Archives Momentum for iOS and macOS and uploads both builds to App Store Connect / TestFlight.
#
#   scripts/testflight.sh            # both platforms
#   scripts/testflight.sh ios        # iPhone only
#   scripts/testflight.sh macos      # Mac only
#   UPLOAD=0 scripts/testflight.sh   # archive + export locally, no upload
#
# Requires: Xcode signed in to team C66WHXJG96, the app record in App Store Connect, and
# `xcodegen` (brew install xcodegen). Build numbers are timestamps so every run is unique.
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORMS=("${@:-ios macos}")
read -r -a PLATFORMS <<< "${PLATFORMS[*]}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
OUT="${OUT:-build/testflight/$BUILD_NUMBER}"
EXPORT_OPTIONS="Config/ExportOptions-AppStore.plist"
mkdir -p "$OUT"

if [[ "${UPLOAD:-1}" == "0" ]]; then
  EXPORT_OPTIONS="$OUT/ExportOptions-local.plist"
  sed 's#<string>upload</string>#<string>export</string>#' Config/ExportOptions-AppStore.plist > "$EXPORT_OPTIONS"
fi

xcodegen generate --quiet

for platform in "${PLATFORMS[@]}"; do
  case "$platform" in
    ios)   destination="generic/platform=iOS" ;;
    macos) destination="generic/platform=macOS" ;;
    *) echo "Unknown platform: $platform (use ios or macos)" >&2; exit 2 ;;
  esac
  archive="$OUT/Momentum-$platform.xcarchive"

  echo "==> Archiving $platform (build $BUILD_NUMBER)"
  xcodebuild archive \
    -project Momentum.xcodeproj -scheme Momentum -configuration Release \
    -destination "$destination" -archivePath "$archive" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    | tee "$OUT/archive-$platform.log" | grep -E "error:|warning: |ARCHIVE" || true
  [[ -d "$archive" ]] || { echo "Archive failed; see $OUT/archive-$platform.log" >&2; exit 1; }

  if [[ "${UPLOAD:-1}" == "0" ]]; then echo "==> Exporting $platform locally"; else echo "==> Uploading $platform to App Store Connect"; fi
  xcodebuild -exportArchive \
    -archivePath "$archive" -exportPath "$OUT/export-$platform" \
    -exportOptionsPlist "$EXPORT_OPTIONS" -allowProvisioningUpdates \
    | tee "$OUT/export-$platform.log" | grep -E "error:|Upload|EXPORT" || true
  grep -q "EXPORT SUCCEEDED" "$OUT/export-$platform.log" || { echo "Export failed; see $OUT/export-$platform.log" >&2; exit 1; }
done

echo "Done. Build $BUILD_NUMBER — processing in App Store Connect usually takes 5–30 minutes."
