<!-- Glance product documentation, modified by EEvan00 in 2026. Original notices retained in NOTICE. -->
# Glance · 一瞥

<img src="Support/AppIcon.svg" width="112" alt="Glance app icon">

A compact native macOS menu bar control panel, maintained by **EEvan00**. Glance brings battery, Wi-Fi, Bluetooth, brightness, volume, playback, Codex usage, weather, date and time into one small popup.

Glance is based on [Status Trio](https://github.com/lingyired/status-trio), originally created by lingyired. The original source history, Apache 2.0 license and applicable third-party notices are preserved. Glance is an independent derivative product, with no claim of endorsement by the original author or Apple.

## Features

- Compact system status cards and brightness / volume controls with detail menus.
- Now Playing controls; a single session includes a seek bar, while simultaneous sessions use a divider because app-specific seeking is unreliable on some sources.
- Codex usage refreshes when opening the popup, with a manual refresh button.
- Apple Weather through two bundled system shortcuts, with UV, daily low/high, sunrise/sunset events and hourly rain chances. Current weather is cached for 15 minutes; detailed forecasts load only when the weather detail menu opens, with a manual refresh button.
- Date, weekday and selectable 12 / 24-hour time display.
- Optional popup scrolling to adjust volume, **off by default**.
- Existing MagSafe LED controls retained from Status Trio.

## Local build

Requires macOS 15 or later. Release acceptance uses Xcode 16.4 / Swift 6.1.2.

```bash
swift test
swift build -c release
bash scripts/build-app.sh release no-open
open dist/Glance.app
```

The app has its own bundle identifier: `io.github.EEvan00.Glance`. SwiftPM package, source modules and test target use the Glance name (`Glance`, `GlanceCore`, `GlanceCoreTests`). Glance copies existing local Status Trio preferences once on first launch; OS permissions and login-item registration are separate for the new app identity.

## Weather setup

Open the weather detail menu to add both bundled shortcuts and confirm the system prompts. Their names are **Glance Weather** and **Glance Weather Forecast**; the app manages the names automatically. macOS may request location access on first use; the app does not silently grant permissions or run an installer script.

## Project and distribution

The project repository is [EEvan00/Glance](https://github.com/EEvan00/Glance), currently private. No public release has been published. Automatic updates remain disabled until Glance has its own Sparkle signing keys and update feed. Future releases use `.github/workflows/release.yml`, explicit version/build numbers and bilingual English / Chinese notes.

Packages built without an available or configured signing identity are ad-hoc signed. Developer ID signing and notarization are not configured. macOS launch constraints reject the ad-hoc Glance MagSafe helper on the tested Mac, so those packages cannot control its LED. Command timeouts and explicit removal handle an unresponsive helper; the ordinary status and weather controls do not require it.

For local development, `scripts/build-app.sh` automatically uses the sole valid Apple Development signing identity when one is available. Set `CODE_SIGN_IDENTITY` explicitly when several identities exist. CI keeps its configured signing behavior. The helper uses the container's stable signing identifier and the `MagSafeLEDHelper` service label to avoid the renamed Status Trio registration's stale executable-path cache. Remove a failed old registration before enabling the new helper, confirm any system authorization prompt, and verify LED control on the Mac. The certificate-signed package was verified to start its helper and apply both system/off commands on the development Mac. Development signing is not Developer ID distribution signing or notarization.

## Popup module

In Settings → Basics, choose Performance (default), Codex usage or Claude usage. Glance only reads the selected usage provider while its popup is open.

Performance reads system CPU load, memory usage and memory pressure once per second while its popup is open. CPU usage is sampled from consecutive system tick counters; the first sample needs one second. The detail menu opens Activity Monitor. No shortcut installation is required. Previously selected Focus or unknown module values fall back to Performance.

Missing weather shortcuts show Add controls in the weather detail menu. Settings → Basics shows installed shortcuts with a Remove in Shortcuts entry; deletion is performed in the system library because the public CLI has no delete operation. Reopening the detail menu checks installation again.

Codex usage uses the existing signed-in Codex installation. Claude usage requires Claude Code: select Claude, open its details and click Connect Claude Code. Glance adds a local collector to Claude Code's status line, preserves the previous command and saves a settings backup under `~/Library/Application Support/Glance/`. After the next Claude Code response, 5-hour and weekly subscription limits become available when Claude Code supplies them. Accounts without those limits show no usage data. The collector stores only usage windows and their update time; it does not read credentials or make API requests. Click refresh to reload collected data; data older than 15 minutes is marked as cached.

To disconnect the Claude collector, restore the `statusLine` entry from `claude-statusline-original.json` in that support directory to `~/.claude/settings.json`, or remove the entry if it was originally empty. Leave other Claude settings intact.

## License and acknowledgements

Glance modifications: © 2026 EEvan00. The bundled icon is retained from Status Trio.
Original Status Trio: © 2026 lingyired.

Licensed under [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for the original and third-party acknowledgements, including the ChargeControl-related BSD notice. Both files are included in the packaged app.
