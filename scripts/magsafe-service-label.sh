#!/usr/bin/env bash
# Stable launchd identity for a packaged MagSafe helper.
set -euo pipefail
bundle_id="$1"
team_id="${2--}"
if [[ ! "$bundle_id" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo 'Invalid bundle identifier.' >&2
    exit 2
fi
if [[ "$team_id" != '-' && ! "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
    echo 'Invalid signing team identifier.' >&2
    exit 2
fi
if [[ "$team_id" == '-' ]]; then
    printf '%s.MagSafeLEDHelper\n' "$bundle_id"
else
    printf '%s.MagSafeLEDHelper.%s\n' "$bundle_id" "$team_id"
fi
