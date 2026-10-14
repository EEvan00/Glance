#!/usr/bin/env bash
# Source this helper; retries only stapler's CloudKit/network error (68).
stapler_with_retry() {
    local attempt=1 status=0 delay=5
    while true; do
        if xcrun stapler "$@"; then
            return 0
        else
            status=$?
        fi
        if [[ "$status" -ne 68 || "$attempt" -ge 4 ]]; then
            return "$status"
        fi
        echo "Apple ticket network request failed (68); retry $attempt/3 in ${delay}s." >&2
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
}
