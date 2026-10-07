# Weather shortcut updates

Imported system shortcuts are independent of the app bundle. Glance compares the revision reported by a successful weather run with `Resources/WeatherShortcutVersions.json`. A legacy output without `GLANCE_VERSION` is revision 0. Unknown revisions are checked by normal weather runs; failures never acknowledge an update.

When changing either workflow:

1. Edit its source under `Support/WeatherShortcuts/`.
2. Increment only its revision in `Sources/GlanceCore/Resources/WeatherShortcutVersions.json`.
3. Run `python3 scripts/build-weather-shortcuts.py` on macOS. This synchronizes the top version comment and final output marker, then signs both importable files. Signing may require network access.
4. Include the manifest, source workflows and signed resources in the app update. Run tests and the release build.

The Weather submenu offers an update for installed shortcuts whose last successful output is older. It opens the bundled file in the system importer. Keep the original shortcut name so Glance runs the intended copy. The same-name importer was verified on the local Mac to offer Replace, Keep Both and Cancel. Choose Replace to update the existing shortcut; matching names do not silently overwrite it. Opening or cancelling the importer does not dismiss the update prompt. The next visible weather run bypasses the normal 15-minute cache to verify the result. The Settings removal controls remain separate.

Validate manually in Shortcuts: run a legacy shortcut, open the Weather submenu, cancel an update and confirm the prompt stays; then import/replace using the original name, return or reopen Weather and confirm the prompt disappears after a successful revisioned run. Repeat for current weather and hourly forecast independently.

Missing shortcuts have one shared setup button in both Settings and the Weather submenu. It opens current weather first, then waits for the installed-name query to confirm installation before offering the hourly forecast. Returning without importing retries the same step; closing the popover preserves in-session progress. Already installed shortcuts are skipped. No second importer is opened automatically.
