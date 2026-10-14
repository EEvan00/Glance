#!/usr/bin/env bash
# Safe to source before building. Reads identities; never creates credentials.
set -euo pipefail

SIGNING_SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

signing_error() { echo "Error: $*" >&2; exit 2; }

# Native WeatherKit is not an available Developer ID capability on macOS. Do not
# accept an unsupported profile/flag and quietly build a nonfunctional app.
if [[ "${WEATHERKIT_ENABLED:-0}" != "0" || -n "${WEATHERKIT_PROVISIONING_PROFILE:-}" ]]; then
    signing_error "WeatherKit is unavailable for Developer ID distribution; use Shortcuts until a separately approved REST proxy exists."
fi
if [[ -n "${WEATHER_SERVICE_URL:-}" ]]; then
    if ! python3 "$SIGNING_SCRIPTS_DIR/validate-weather-service-url.py" "$WEATHER_SERVICE_URL"; then
        signing_error "WEATHER_SERVICE_URL must be a public HTTPS endpoint ending in /v1/weather, without credentials, query, or fragment."
    fi
fi
if [[ "${CODE_SIGN_IDENTITY+x}" == x && -z "$CODE_SIGN_IDENTITY" ]]; then
    signing_error "An explicitly configured CODE_SIGN_IDENTITY must not be empty."
fi
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGNING_KIND=adhoc
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    [[ -z "${NOTARY_PROFILE:-}" ]] || signing_error "NOTARY_PROFILE requires Developer ID Application signing."
    [[ -z "${INSTALLER_SIGN_IDENTITY:-}" ]] || signing_error "INSTALLER_SIGN_IDENTITY requires certificate-backed application signing."
else
    if [[ "$SIGNING_IDENTITY" == 'Developer ID Application: '* && -z "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
        signing_error "Developer ID distribution requires INSTALLER_SIGN_IDENTITY for the legacy migration uninstaller."
    fi
    KEYCHAIN_ARGS=()
    if [[ -n "${KEYCHAIN_PATH:-}" ]]; then
        [[ -f "$KEYCHAIN_PATH" ]] || signing_error "KEYCHAIN_PATH does not exist."
        KEYCHAIN_ARGS+=("$KEYCHAIN_PATH")
    fi
    RESOLVED_IDENTITY=""
    while IFS= read -r identity_line; do
        if [[ "$identity_line" =~ ([A-Fa-f0-9]{40})\ \"([^\"]+)\" ]]; then
            if [[ "$SIGNING_IDENTITY" == "${BASH_REMATCH[1]}" || "$SIGNING_IDENTITY" == "${BASH_REMATCH[2]}" ]]; then
                RESOLVED_IDENTITY="${BASH_REMATCH[2]}"
                break
            fi
        fi
    done < <(security find-identity -v -p codesigning ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} 2>/dev/null)
    [[ -n "$RESOLVED_IDENTITY" ]] || signing_error "CODE_SIGN_IDENTITY is not available as a valid code signing identity."
    SIGNING_KIND=certificate
    if [[ "$RESOLVED_IDENTITY" == 'Developer ID Application: '* ]]; then
        SIGNING_KIND=developerID
        [[ -n "${INSTALLER_SIGN_IDENTITY:-}" ]] || signing_error "Developer ID distribution requires INSTALLER_SIGN_IDENTITY for the legacy migration uninstaller."
        [[ "$INSTALLER_SIGN_IDENTITY" == 'Developer ID Installer: '* ]] || signing_error "INSTALLER_SIGN_IDENTITY must be a Developer ID Installer identity."
        # Match teams as well as certificate types. These names come from valid
        # Keychain identities, not user-controlled app metadata.
        APP_SIGNING_TEAM="${RESOLVED_IDENTITY##*(}"
        INSTALLER_SIGNING_TEAM="${INSTALLER_SIGN_IDENTITY##*(}"
        [[ "$APP_SIGNING_TEAM" == "$INSTALLER_SIGNING_TEAM" ]] || signing_error "Application and Installer identities must belong to the same team."
        INSTALLER_AVAILABLE=false
        while IFS= read -r identity_line; do
            if [[ "$identity_line" =~ ([A-Fa-f0-9]{40})\ \"([^\"]+)\" ]]; then
                if [[ "${BASH_REMATCH[2]}" == "$INSTALLER_SIGN_IDENTITY" ]]; then
                    INSTALLER_AVAILABLE=true
                    break
                fi
            fi
        done < <(security find-identity -v ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} 2>/dev/null)
        [[ "$INSTALLER_AVAILABLE" == true ]] || signing_error "INSTALLER_SIGN_IDENTITY is not available as a valid signing identity."
    elif [[ -n "${NOTARY_PROFILE:-}" || -n "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
        signing_error "Notarization and Developer ID Installer signing require Developer ID Application signing."
    fi
fi
