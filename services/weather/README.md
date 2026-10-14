# Glance Apple Weather service

The WeatherKit REST service is deployed at
`https://glance-weather-service.pengyimm.workers.dev/v1/weather`.
Glance's Developer ID distribution uses this REST service. Apple credentials
remain in Cloudflare encrypted Secrets and never enter the application or Git.

## Request contract

`GET /v1/weather?latitude=-33.87&longitude=151.21&language=en&timezone=Australia%2FSydney`

The Worker accepts only these four parameters, with no duplicates. Latitude and
longitude must be finite decimal coordinates in range, rounded again to two
places on the server. Only `en` is supported; the app localizes condition labels.
The timezone must resolve as a valid IANA timezone. Arbitrary URLs, token endpoints,
extra paths, HTTP redirects and other methods are rejected.

A successful JSON result is:

```json
{
  "weather": {
    "currentWeather": {},
    "forecastHourly": {"hours": []},
    "forecastDaily": {"days": []}
  },
  "attribution": {
    "combinedMarkLightURL": "https://weatherkit.apple.com/…",
    "combinedMarkDarkURL": "https://weatherkit.apple.com/…",
    "legalPageURL": "https://weatherkit.apple.com/…"
  }
}
```

The actual datasets are passed from Apple's REST response after shape/size checks.
The request asks for current weather, the next 24 hours and up to 48 hours of daily
weather. The two mark URLs come dynamically from Apple's `logoLight@2x` and
`logoDark@2x` attribution fields. The legal link comes from
`currentWeather.metadata.attributionURL`. Logo links remain on `https://weatherkit.apple.com`; the legal link may also be
the exact `https://developer.apple.com/weatherkit/data-source-attribution/` page.
The server fetches attribution from `/attribution/en` and never fetches legal URLs
or arbitrary URLs.
Fixture filenames identify white and black marks; render the white mark on a dark
surface and the black mark on a light surface. The client displays the mark and
legal link whenever native weather is displayed.

Errors contain only `{ "error": "<stable code>" }`, with `Cache-Control: no-store`.
They never include upstream response bodies, coordinates, IPs, identifiers,
private-key text or JWTs. `429` means `rate_limited` or `quota_exceeded`; `503`
means unconfigured/unavailable storage or `service_busy`; `502` and `504` indicate
upstream response/timeout failures. No automated retry occurs on the server.

## Free-plan limits and abuse

**Use a Cloudflare Workers Free account plan only. Do not enable Workers Paid,
paid WeatherKit subscriptions, automatic upgrades, or custom-domain routes.**
The Wrangler file cannot select, enforce or inspect the Cloudflare account plan.
Confirm the account's plan in Cloudflare before any future deployment.

Workers and SQLite-backed Durable Objects are available on Free. Exceeding
Cloudflare's free resource allowance fails further operations; service can stop.
This is an availability tradeoff. Do not upgrade to paid service to mask overload.
The singleton DO also reserves every upstream HTTP attempt durably before making
it, including failed requests and attribution requests. Defaults are 400,000 calls
per UTC calendar month and 15,000 per UTC day; variables may lower these caps but
cannot increase them above these ceilings. No quota refunds are issued after
errors. The counters survive eviction, restart and code deployment. Do not delete
or restore/reset the `global-weather-v1` object's data or change its singleton
name: doing so resets quota history. Only this service's Apple calls are counted;
other apps using the same Apple developer subscription must leave additional
headroom or lower this service's caps.

Every incoming request reaching the DO, including cache hits, is limited to 20 per
IP per UTC minute and 300 per IP per day by default (both may be lowered). The
Worker trusts only Cloudflare's edge-provided `CF-Connecting-IP`, hashes it with
the UTC day, and forwards the hash rather than the raw IP. At most 2,048 IP hash
records are admitted per UTC day; new IPs then receive `429`. Records are deleted
on the next day's first request. These coarse limits may affect shared networks.
This is an abuse control, not authentication: the public endpoint can be used by
anyone, distributed attackers can consume the global quota, and accepted requests
may stop for everyone until the next quota period. A shared secret embedded in
the app would not fix that and is intentionally absent.

The 15-minute weather cache holds at most 64 rounded-location/timezone results.
Identical in-flight requests share one request; at most eight unique loads are
active at once. Attribution and the server-only five-minute ES256 token are also
coalesced/cached. Cache results and approximate coordinates exist only in DO
memory and disappear on eviction/restart. Quotas and daily date-prefixed IP hashes use
the SQLite-backed DO's key-value API, which is supported on SQLite storage.
Each Apple request has an eight-second timeout and a 256 KiB response limit.

Code emits no logs, and Wrangler observability is disabled. Avoid enabling request
logging/tail collectors because URLs contain approximate coordinates. Cloudflare
itself still receives the incoming IP and URL; Apple receives rounded coordinates
from the service. The daily SHA-256 of date:IP is pseudonymization, not anonymity; IP addresses can be guessed from the hash. The selected service operator is
responsible for the same privacy promises made by the client.

**These controls do not bound Cloudflare request charges on a paid account.**
Rejected public requests still reach Cloudflare and may incur paid-plan request,
compute or storage charges. The code cannot make a public paid deployment
cost-free. Free plan limits, plus no paid upgrades, are the required operational
boundary. The live Free-plan resource/CPU budget remains unverified. SQLite Free currently allows 100,000 rows written per day: rate updates, quota reservations and cleanup all consume writes, so this allowance may stop service before the Apple-call cap is reached. Persistence errors fail closed before a new Apple call.

## Future setup (membership active per user report)

The setup below has now been completed for the deployed endpoint. Apple
Services ID is `com.gadels.glance.weather`; a dedicated WeatherKit-only key is
stored in a restricted operator-side directory and Cloudflare encrypted Secrets.
No private key is stored in Git or the application. Wrangler authorization is
limited to account/user reads, Workers scripts/Secrets/DO edits and background
access, using the macOS Keychain. Future credential rotation follows these steps.

1. In the Apple Developer portal create a WeatherKit-enabled key and a Service ID
   following [Apple's authentication instructions](https://developer.apple.com/documentation/weatherkitrestapi/request-authentication-for-weatherkit-rest-api).
   Keep the downloaded `.p8` PKCS#8 P-256 private key on the server/operator side.
2. Confirm Workers **Free** in the Cloudflare account. Use the included SQLite
   `new_sqlite_classes` migration and the `workers.dev` hostname. A domain purchase
   or custom-domain configuration is unnecessary.
3. Supply these as Worker secrets through Cloudflare's interactive secret tool;
   never place values in `wrangler.toml`, Git, app bundles or terminal command
   arguments:

   ```sh
   wrangler secret put APPLE_WEATHER_PRIVATE_KEY
   wrangler secret put APPLE_WEATHER_TEAM_ID
   wrangler secret put APPLE_WEATHER_KEY_ID
   wrangler secret put APPLE_WEATHER_SERVICE_ID
   ```

   The key is the actual multiline PEM, not a base64 wrapper or escaped `\n` text.
   Team ID and key ID are ten uppercase alphanumeric characters. Service ID must
   exactly match the registered Service ID.
4. A later explicitly authorized deployment can use this directory's
   `wrangler.toml`. After deployment, check account plan/usage, all API responses,
   JWT authentication, public abuse controls, timeout behavior and quota counters
   before giving the app the actual HTTPS workers.dev `/v1/weather` URL.
5. Package the app with that URL as `GlanceWeatherServiceURL` and inspect the
   localized location permission text. Confirm actual location authorization,
   Apple response mapping, official mark contrast, legal link and fallback choice
   on a real Mac. No live success is implied by offline tests.

## Offline verification

No npm dependencies are needed for these tests. With Node 22 or newer:

```sh
npm test --prefix services/weather
```

Tests generate a disposable P-256 key in memory, cryptographically verify Apple
JWT claims/signature, exercise cache/coalescing/input/errors, and reconstruct
service/storage instances over an atomic fake database to check persistent quota
and IP-rate behavior. The Cloudflare runtime, real SQLite transactions, Free CPU
limits and real Apple authentication are separate live checks. Node tests do not
prove those external states.

Primary references checked during implementation:

- [Apple REST weather query](https://developer.apple.com/documentation/weatherkitrestapi/get-api-v1-weather-_language_-_latitude_-_longitude_)
- [Apple REST attribution schema](https://developer.apple.com/documentation/weatherkitrestapi/attribution)
- [Cloudflare SQLite storage and transactions](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/)
- [Cloudflare Free SQLite Durable Objects and limits](https://developers.cloudflare.com/durable-objects/platform/pricing/)
- [Cloudflare Worker plan limits](https://developers.cloudflare.com/workers/platform/limits/)

Runtime integration notes: Cloudflare uses manual redirect handling and rejects
all redirects. The default native fetch retains its Worker-global receiver.
Safe error headers contain fixed failure categories and optional numeric upstream
status only; no raw error, upstream body or authentication token is returned.
Live attribution uses `/attribution/en`; light appearance supplies black artwork,
dark appearance supplies white artwork. Offline Node suite:20 tests passed.

## Near-midnight forecast fix (2026-10-15)

An omitted `hourlyStart` let Apple's default forecast include earlier hours of
that local day. Near midnight, the result exceeded the service's 48-hour-entry
limit and was rejected with HTTP 502. At local midnight the returned range
shrank again, explaining intermittent recovery.

The service now sends an explicit `hourlyStart` and `hourlyEnd` 24 hours apart.
The 48-entry response cap, payload cap, credentials, quotas and caching remain.
Sanitized failure stages distinguish temperature, hourly/daily shape and count
validation without returning locations, authentication or upstream response data.

22 Node tests passed. After deployment, Sydney, Brisbane, Guam, Tokyo and London
time-zone probes returned 24 hourly entries; Brisbane and Guam previously failed
with `weather-hourly-count`. Deployment: `7d7fe251-10b3-4f9d-832c-b548c948a74c`.
The app remains 2.0.0 Build 18; this fix does not require a new app download.
