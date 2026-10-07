#!/usr/bin/env bash
# Glance modifications by EEvan00, 2026. Original project notices: NOTICE.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"
OPEN_APP="${2:-open}"
BUNDLE_ID="${BUNDLE_ID:-io.github.EEvan00.Glance}"
APP_NAME="${APP_NAME:-Glance}"
APP_VERSION="${APP_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
FORK_REVISION="${FORK_REVISION:-$(/usr/libexec/PlistBuddy -c "Print :GlanceForkRevision" "$ROOT/Support/Info.plist")}"
SU_FEED_URL="${SU_FEED_URL:-}"
UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-0}"
AUTOMATIC_UPDATES_ENABLED="${AUTOMATIC_UPDATES_ENABLED:-0}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"

case "$OPEN_APP" in
    open|no-open) ;;
    *)
        echo "Usage: $0 [configuration] [open|no-open]" >&2
        exit 2
        ;;
esac

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "Error: BUNDLE_ID may contain only letters, numbers, periods, and hyphens." >&2
    exit 2
fi

if [[ -z "$APP_NAME" ]]; then
    echo "Error: APP_NAME must not be empty." >&2
    exit 2
fi

if [[ -n "$APP_VERSION" && ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "Error: APP_VERSION must contain dot-separated numbers, for example 1.2.0." >&2
    exit 2
fi

if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: BUILD_NUMBER must contain only digits." >&2
    exit 2
fi

if [[ ! "$FORK_REVISION" =~ ^[0-9]+$ || "$FORK_REVISION" == "0" ]]; then
    echo "Error: FORK_REVISION must be a positive integer." >&2
    exit 2
fi

if [[ -n "$SU_FEED_URL" && "$SU_FEED_URL" != https://* ]]; then
    echo "Error: SU_FEED_URL must use HTTPS." >&2
    exit 2
fi

case "$UNIVERSAL_BUILD" in
    0|1) ;;
    *)
        echo "Error: UNIVERSAL_BUILD must be 0 or 1." >&2
        exit 2
        ;;
esac

case "$AUTOMATIC_UPDATES_ENABLED" in
    0|1) ;;
    *)
        echo "Error: AUTOMATIC_UPDATES_ENABLED must be 0 or 1." >&2
        exit 2
        ;;
esac

if [[ "$AUTOMATIC_UPDATES_ENABLED" == "1" && ( -z "$SU_FEED_URL" || -z "$SPARKLE_PUBLIC_KEY" ) ]]; then
    echo "Error: Sparkle builds require SU_FEED_URL and SPARKLE_PUBLIC_KEY." >&2
    exit 2
fi

cd "$ROOT"

SWIFT_BUILD_ARGS=(build -c "$CONFIGURATION")
if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
    SWIFT_BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

swift "${SWIFT_BUILD_ARGS[@]}"
BIN_PATH="$(swift "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="$ROOT/dist/Glance.app"
CONTENTS="$APP_DIR/Contents"
ICON_SOURCE="$ROOT/Support/AppIcon.svg"
ICONSET_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/Glance.XXXXXX")"
ICONSET_DIR="$ICONSET_ROOT/AppIcon.iconset"

trap 'rm -rf "$ICONSET_ROOT"' EXIT

sips -s format png -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_ROOT/AppIcon.png" >/dev/null
mkdir -p "$ICONSET_DIR"

while read -r pixel filename; do
    sips -z "$pixel" "$pixel" "$ICONSET_ROOT/AppIcon.png" --out "$ICONSET_DIR/$filename" >/dev/null
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES

rm -rf "$APP_DIR"
mkdir -p \
    "$CONTENTS/MacOS" \
    "$CONTENTS/Resources" \
    "$CONTENTS/Frameworks" \
    "$CONTENTS/Library/LaunchDaemons"

CORE_RESOURCE_BUNDLE="$BIN_PATH/Glance_GlanceCore.bundle"
if [[ ! -d "$CORE_RESOURCE_BUNDLE" ]]; then
    echo "Error: missing SwiftPM resource bundle at $CORE_RESOURCE_BUNDLE." >&2
    exit 1
fi

cp "$BIN_PATH/Glance" "$CONTENTS/MacOS/Glance"
cp "$BIN_PATH/libGlanceMediaBridge.dylib" "$CONTENTS/Frameworks/libGlanceMediaBridge.dylib"
cp -R "$CORE_RESOURCE_BUNDLE" "$CONTENTS/Resources/"
cp "$BIN_PATH/GlanceMagSafeHelper" "$CONTENTS/Resources/GlanceMagSafeHelper"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$CONTENTS/Resources/"
cp "$ROOT/Support/io.github.EEvan00.Glance.magsafe-helper.plist" "$CONTENTS/Library/LaunchDaemons/io.github.EEvan00.Glance.magsafe-helper.plist"
MAGSAFE_HELPER_LABEL="$BUNDLE_ID.MagSafeLEDHelper"
MAGSAFE_MACH_SERVICE="$BUNDLE_ID.MagSafeHelper"
/usr/libexec/PlistBuddy \
    -c "Set :Label $MAGSAFE_HELPER_LABEL" \
    -c "Delete :MachServices" \
    -c "Add :MachServices dict" \
    -c "Add :MachServices:$MAGSAFE_MACH_SERVICE bool true" \
    -c "Set :EnvironmentVariables:GLANCE_MACH_SERVICE $MAGSAFE_MACH_SERVICE" \
    "$CONTENTS/Library/LaunchDaemons/io.github.EEvan00.Glance.magsafe-helper.plist"

SPARKLE_FRAMEWORK_SOURCE="$(find "$ROOT/.build/artifacts" -path '*/Sparkle.xcframework/macos-*/Sparkle.framework' -type d -print -quit)"
if [[ -z "$SPARKLE_FRAMEWORK_SOURCE" ]]; then
    echo "Error: missing Sparkle.framework under .build/artifacts." >&2
    exit 1
fi

ditto "$SPARKLE_FRAMEWORK_SOURCE" "$CONTENTS/Frameworks/Sparkle.framework"

if ! otool -l "$CONTENTS/MacOS/Glance" | grep -Fq 'path @executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$CONTENTS/MacOS/Glance"
fi

cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$CONTENTS/Info.plist"

if [[ -n "$APP_VERSION" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS/Info.plist"
fi

if [[ -n "$BUILD_NUMBER" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
fi

/usr/libexec/PlistBuddy -c "Set :GlanceForkRevision $FORK_REVISION" "$CONTENTS/Info.plist"

if [[ "$AUTOMATIC_UPDATES_ENABLED" == "1" ]]; then
    /usr/libexec/PlistBuddy -c "Set :GlanceEnableSparkle true" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SU_FEED_URL" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$CONTENTS/Info.plist"
else
    /usr/libexec/PlistBuddy -c "Set :GlanceEnableSparkle false" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Delete :SUEnableAutomaticChecks" "$CONTENTS/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$CONTENTS/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$CONTENTS/Info.plist" 2>/dev/null || true
fi
INFO_PLIST_COUNT="$(find "$ROOT/Sources/GlanceCore/Resources" -name 'InfoPlist.strings' -type f | wc -l | tr -d ' ')"
if [[ "$INFO_PLIST_COUNT" -ne 12 ]]; then
    echo "Error: expected 12 localized InfoPlist.strings files, found $INFO_PLIST_COUNT." >&2
    exit 1
fi

while IFS= read -r source; do
    language_dir="$(basename "$(dirname "$source")")"
    target_dir="$CONTENTS/Resources/$language_dir"
    mkdir -p "$target_dir"
    cp "$source" "$target_dir/InfoPlist.strings"
done < <(find "$ROOT/Sources/GlanceCore/Resources" -name 'InfoPlist.strings' -type f | sort)

iconutil --convert icns --output "$CONTENTS/Resources/AppIcon.icns" "$ICONSET_DIR"

chmod +x \
    "$CONTENTS/MacOS/Glance" \
    "$CONTENTS/Resources/GlanceMagSafeHelper"

# SwiftPM can record the deployment target as the SDK version in LC_BUILD_VERSION.
# macOS uses that field to decide whether an app adopts the current design system,
# so restore the real SDK version before signing.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${SDK_VERSION%%.*}" -ge 26 ]]; then
    TOOLCHAIN_PLATFORM_VERSION="26.0"
    restore_deployment_target() {
        local binary="$1"
        local temporary_binary
        temporary_binary="$(mktemp "${TMPDIR:-/tmp}/Glance.vtool.XXXXXX")"
        xcrun vtool \
            -set-build-version macos 15.0 "$TOOLCHAIN_PLATFORM_VERSION" \
            -replace \
            -output "$temporary_binary" \
            "$binary"
        mv "$temporary_binary" "$binary"
        chmod +x "$binary"
    }

    restore_deployment_target "$CONTENTS/MacOS/Glance"
    restore_deployment_target "$CONTENTS/Resources/GlanceMagSafeHelper"
fi

SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
# Local updates must preserve a certificate-backed identity for SMAppService.
# CI and explicit release signing continue to use their configured identity.
if [[ -z "$SIGNING_IDENTITY" && "${CI:-false}" != "true" ]]; then
    LOCAL_DEVELOPMENT_IDENTITIES=()
    while IFS= read -r identity; do
        [[ -n "$identity" ]] && LOCAL_DEVELOPMENT_IDENTITIES+=("$identity")
    done < <(security find-identity -v -p codesigning 2>/dev/null \
        | sed -nE 's/^[[:space:]]*[0-9]+\) ([A-Fa-f0-9]{40}) "Apple Development:.*$/\1/p')
    if [[ "${#LOCAL_DEVELOPMENT_IDENTITIES[@]}" -eq 1 ]]; then
        SIGNING_IDENTITY="${LOCAL_DEVELOPMENT_IDENTITIES[0]}"
    fi
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SIGNING_ARGS=(--force --deep --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    SIGNING_ARGS+=(--options runtime --timestamp)
    if [[ -n "${KEYCHAIN_PATH:-}" ]]; then
        SIGNING_ARGS+=(--keychain "$KEYCHAIN_PATH")
    fi
fi

codesign "${SIGNING_ARGS[@]}" "$CONTENTS/Frameworks/libGlanceMediaBridge.dylib"
codesign "${SIGNING_ARGS[@]}" "$CONTENTS/Frameworks/Sparkle.framework"
# SMAppService may retain the container's signing identifier in its launch
# requirement. A standalone SwiftPM executable otherwise gets a UUID-derived
# identifier that changes across builds and does not match the container.
codesign "${SIGNING_ARGS[@]}" --identifier "$BUNDLE_ID" "$CONTENTS/Resources/GlanceMagSafeHelper"
# Hardened Runtime requires this entitlement before macOS can show the
# location permission prompt used by the existing Wi-Fi authorization flow.
plutil -lint "$ROOT/Support/Glance.entitlements"
codesign "${SIGNING_ARGS[@]}" --entitlements "$ROOT/Support/Glance.entitlements" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

plutil -lint "$CONTENTS/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CONTENTS/Info.plist")" == "$BUNDLE_ID" ]] || {
    echo "Error: packaged CFBundleIdentifier does not match the requested bundle identifier." >&2
    exit 1
}
[[ -f "$CONTENTS/Resources/AppIcon.icns" ]] || { echo "Error: packaged app icon is missing." >&2; exit 1; }
[[ -d "$CONTENTS/Resources/Glance_GlanceCore.bundle" ]] || { echo "Error: packaged resource bundle is missing." >&2; exit 1; }
[[ -x "$CONTENTS/Resources/GlanceMagSafeHelper" ]] || { echo "Error: packaged MagSafe helper is missing." >&2; exit 1; }
[[ -f "$CONTENTS/Library/LaunchDaemons/io.github.EEvan00.Glance.magsafe-helper.plist" ]] || { echo "Error: packaged MagSafe launch daemon plist is missing." >&2; exit 1; }
plutil -lint "$CONTENTS/Library/LaunchDaemons/io.github.EEvan00.Glance.magsafe-helper.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$CONTENTS/Library/LaunchDaemons/io.github.EEvan00.Glance.magsafe-helper.plist")" == "$MAGSAFE_HELPER_LABEL" ]] || {
    echo "Error: packaged MagSafe helper label does not match the app bundle identifier." >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:GLANCE_MACH_SERVICE' "$CONTENTS/Library/LaunchDaemons/io.github.EEvan00.Glance.magsafe-helper.plist")" == "$MAGSAFE_MACH_SERVICE" ]] || {
    echo "Error: packaged MagSafe XPC service environment does not match the expected Mach service." >&2
    exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c "Print :MachServices:$MAGSAFE_MACH_SERVICE" "$CONTENTS/Library/LaunchDaemons/io.github.EEvan00.Glance.magsafe-helper.plist")" == "true" ]] || {
    echo "Error: packaged MagSafe Mach service does not match the expected XPC endpoint." >&2
    exit 1
}
codesign --verify --strict --verbose=2 "$CONTENTS/Resources/GlanceMagSafeHelper"

if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
    verify_universal_binary() {
        local binary="$1"
        local architectures
        architectures="$(lipo -archs "$binary")"
        if [[ "$architectures" != *"arm64"* || "$architectures" != *"x86_64"* ]]; then
            echo "Error: expected universal arm64+x86_64 binary: $binary ($architectures)" >&2
            exit 1
        fi
    }

    verify_universal_binary "$CONTENTS/MacOS/Glance"
    verify_universal_binary "$CONTENTS/Resources/GlanceMagSafeHelper"
    while IFS= read -r binary; do
        if file "$binary" | grep -q 'Mach-O'; then
            verify_universal_binary "$binary"
        fi
    done < <(find "$CONTENTS/Frameworks" -type f -perm -111)
fi

if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
    DYNAMIC_LIBRARY_ENTRIES="$(
        for architecture in arm64 x86_64; do
            otool -arch "$architecture" -L "$CONTENTS/MacOS/Glance" | tail -n +2
        done
    )"
else
    DYNAMIC_LIBRARY_ENTRIES="$(otool -L "$CONTENTS/MacOS/Glance" | tail -n +2)"
fi
if printf '%s\n' "$DYNAMIC_LIBRARY_ENTRIES" | grep -Eq '(/Users/|/private/var/)'; then
    echo "Error: packaged executable contains a developer-machine dynamic-library reference." >&2
    exit 1
fi

echo "Built $APP_DIR (bundle id: $BUNDLE_ID)"

if [[ "$OPEN_APP" == "open" ]]; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

    for _ in {1..20}; do
        if [[ -z "$(lsappinfo find bundleID="$BUNDLE_ID" 2>/dev/null || true)" ]]; then
            break
        fi
        sleep 0.1
    done

    if [[ -n "$(lsappinfo find bundleID="$BUNDLE_ID" 2>/dev/null || true)" ]]; then
        echo "Error: $APP_NAME ($BUNDLE_ID) is still running after the graceful quit wait; refusing to open the rebuilt bundle." >&2
        exit 1
    fi

    open "$APP_DIR"
fi
