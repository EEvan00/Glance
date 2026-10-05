# Weather shortcut sources

These editable workflow files produce the two signed shortcuts bundled in Glance.
Sign them with the built-in macOS command before packaging:

```sh
shortcuts sign --mode anyone --input "Support/WeatherShortcuts/Glance Weather.wflow" --output "Sources/GlanceCore/Resources/Glance Weather.shortcut"
shortcuts sign --mode anyone --input "Support/WeatherShortcuts/Glance Weather Forecast.wflow" --output "Sources/GlanceCore/Resources/Glance Weather Forecast.shortcut"
```

Current weather outputs temperature, condition and a `UV` section. Detailed weather also outputs `LOW`, `HIGH`, `DATES`, `HOURS`, `LOCATION`, `SUNRISE`, `SUNSET` and `RAIN_CHANCES` (one value per hourly date). Dates use ISO 8601 with time zone offsets. Keep the section markers unchanged: `WeatherSnapshot.fromShortcut` parses them.

Updating the bundled resources does not replace installed shortcuts automatically. Use the Add current weather and Add forecast buttons in Settings, then choose Replace in Shortcuts. The app keeps the existing 15-minute cache and only loads detailed forecasts while the weather menu is open. Manual refresh bypasses the cache once.
