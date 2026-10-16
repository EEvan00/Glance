# Weather shortcut source

`Glance Weather.wflow` produces the single signed shortcut bundled in Glance. It returns current weather and the hourly forecast in one execution. Rebuild the importable resource after changing the workflow or its revision:

```sh
python3 scripts/build-weather-shortcuts.py
```

The output starts with current temperature and condition, followed by `LOW`, `HIGH`, `DATES`, `HOURS`, `LOCATION`, `UV`, `SUNRISE`, `SUNSET`, `RAIN_CHANCES`, `RAIN_CHANCE`, and `GLANCE_VERSION` sections. `RAIN_CHANCE` is the current probability; `RAIN_CHANCES` contains one probability per hourly date. Dates use ISO 8601 with time zone offsets. Keep section markers unchanged: `WeatherSnapshot.fromShortcut` parses them.

`SUNRISE` and `SUNSET` contain one date per day from the daily forecast. Glance inserts the events that fall inside the hourly forecast range, including the next day's solar events. Legacy single-date and current-only output remains supported.

Version 2 combines the former current/forecast workflows under **Glance Weather**. An installed version 1 continues to supply current weather and offers an update once its output has been read. Choose Update in the weather page or weather settings and Replace in the system importer. Installation clicks alone never acknowledge an update: the shortcut must execute successfully and report the new version.

The old **Glance Weather Forecast** shortcut is no longer bundled or executed. Glance does not delete it from the user's Shortcuts library. Summary and detail views share one controller, one execution, and the existing 15-minute cache; manual refresh bypasses the cache.
