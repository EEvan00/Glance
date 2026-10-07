#!/bin/bash
set -euo pipefail
APP="$1"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
LABEL=io.github.EEvan00.Glance.MagSafeLEDHelper
ROOT="$TEMP/root"
mkdir -p "$ROOT/Library/PrivilegedHelperTools" "$ROOT/Library/LaunchDaemons" "$ROOT/Library/Application Support/GlanceHelper" "$TEMP/install" "$TEMP/uninstall" "$TEMP/empty"
cp "$APP/Contents/Resources/GlanceMagSafeHelper" "$ROOT/Library/PrivilegedHelperTools/$LABEL"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" > "$ROOT/Library/Application Support/GlanceHelper/expected-build"
cat > "$ROOT/Library/LaunchDaemons/$LABEL.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>io.github.EEvan00.Glance.MagSafeLEDHelper</string>
<key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/io.github.EEvan00.Glance.MagSafeLEDHelper</string></array>
<key>MachServices</key><dict><key>io.github.EEvan00.Glance.MagSafeHelper</key><true/></dict>
<key>EnvironmentVariables</key><dict><key>GLANCE_MACH_SERVICE</key><string>io.github.EEvan00.Glance.MagSafeHelper</string><key>GLANCE_LEGACY_HELPER</key><string>1</string></dict>
</dict></plist>
PLIST
cat > "$TEMP/install/preinstall" <<'SCRIPT'
#!/bin/bash
set -eu
for path in '/Library/Application Support' /Library/PrivilegedHelperTools /Library/LaunchDaemons '/Library/Application Support/GlanceHelper' /Library/PrivilegedHelperTools/io.github.EEvan00.Glance.MagSafeLEDHelper /Library/LaunchDaemons/io.github.EEvan00.Glance.MagSafeLEDHelper.plist; do
 if [[ -L "$path" ]]; then echo 'Unsafe helper installation path.' >&2; exit 1; fi
 if [[ -e "$path" && "$(/usr/bin/stat -f '%u' "$path")" != 0 ]]; then echo 'Helper installation path is not root-owned.' >&2; exit 1; fi
done
SCRIPT
cat > "$TEMP/install/postinstall" <<'SCRIPT'
#!/bin/bash
set -eu
app=/Applications/Glance.app
label=io.github.EEvan00.Glance.MagSafeLEDHelper
config='/Library/Application Support/GlanceHelper'
/usr/bin/codesign --verify --deep --strict "$app"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
[[ "$build" == "$(cat "$config/expected-build")" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == io.github.EEvan00.Glance ]]
/bin/launchctl bootout "system/$label" >/dev/null 2>&1 || true
/bin/rm -f "$config/ready"
"/Library/PrivilegedHelperTools/$label" --configure-installation
/usr/sbin/chown -R root:wheel "$config"
/bin/chmod 755 "$config"
/bin/chmod 644 "$config/installation.json"
/bin/chmod 755 "/Library/PrivilegedHelperTools/$label"
/bin/chmod 644 "/Library/LaunchDaemons/$label.plist"
/bin/launchctl bootstrap system "/Library/LaunchDaemons/$label.plist"
/usr/bin/touch "$config/ready"
SCRIPT
cat > "$TEMP/uninstall/postinstall" <<'SCRIPT'
#!/bin/bash
set -eu
label=io.github.EEvan00.Glance.MagSafeLEDHelper
binary="/Library/PrivilegedHelperTools/$label"
if [[ -x "$binary" && ! -L "$binary" && "$(/usr/bin/stat -f '%u' "$binary")" == 0 ]]; then
 "$binary" --restore-system || echo 'Unable to restore LED control before removal.' >&2
fi
/bin/launchctl bootout "system/$label" >/dev/null 2>&1 || true
/bin/rm -f "/Library/LaunchDaemons/$label.plist" "$binary"
/bin/rm -rf '/Library/Application Support/GlanceHelper'
/usr/sbin/pkgutil --forget io.github.EEvan00.Glance.HelperInstall >/dev/null 2>&1 || true
SCRIPT
chmod 755 "$TEMP/install/preinstall" "$TEMP/install/postinstall" "$TEMP/uninstall/postinstall"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
pkgbuild --root "$ROOT" --scripts "$TEMP/install" --identifier io.github.EEvan00.Glance.HelperInstall --version "$VERSION" --install-location / "$APP/Contents/Resources/GlanceHelperInstall.pkg"
pkgbuild --root "$TEMP/empty" --scripts "$TEMP/uninstall" --identifier io.github.EEvan00.Glance.HelperUninstall --version "$VERSION" --install-location / "$APP/Contents/Resources/GlanceHelperUninstall.pkg"
