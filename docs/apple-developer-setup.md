# Apple Developer setup (prepared; membership active per user report)

Local setup update (2026-10-13): the user reports active membership. Developer ID
Application and Developer ID Installer identities were created through Xcode and
verified as valid local identities with private keys. The user stored an
app-specific-password profile named `Glance-Notary` in the local Keychain;
`notarytool history` authenticated successfully. No password or private key was
exported into this repository.

The complete local app passed Developer ID signing and strict/deep codesign
verification, including Hardened Runtime and trusted timestamps. The migration
uninstaller also passed Developer ID Installer signature verification. Apple accepted migration-package submission
`4bbd0701-4d2d-41f8-97bb-07921eb001da`; its stapled ticket validates. The builder
then sealed and verified the full app. The full-app archive submission
`7ea9a596-d366-4771-b266-af4569f511e4` was Accepted. The exact signed app at
`dist/notarization-validation/Glance.app` passed stapler staple/validate, strict
codesign verification and Gatekeeper assessment (`source=Notarized Developer ID`).
The monitoring heartbeat is now paused. Apple submission log is saved alongside
the app. This validates the local app artifact; DMG, CI and public release remain
separate delivery checks. Initial signing
attempts failed because Keychain access prompts were cancelled (confirmed in
securityd logs and by the user); those failures do not indicate notarization
acceptance. CI secrets, backend deployment, helper authorization and physical
MagSafe operation remain separate checks. No GitHub publication has occurred.

## Signing and MagSafe distribution

`scripts/build-app.sh` writes `GlanceMagSafeHelperStrategy` explicitly:

| Signing mode | Helper installation | Bundled packages |
| --- | --- | --- |
| Ad-hoc (`CODE_SIGN_IDENTITY=-`) | Existing administrator-authorized legacy Installer | Install and uninstall |
| Certificate backed (Apple Development / Developer ID) | Bundled `SMAppService.daemon` | Migration uninstall only |

The certificate path never selects the old installation package merely because a
package is present. A current old helper still requires migration: the user starts
Install in the app, the existing Installer uninstall package requests administrator
authorization, and registration runs only after all known legacy files disappear.
Cancellation, uninstall failure, and remaining files stop migration. System
Settings approval remains a separate `requiresApproval` state. A fresh certificate
build registers the bundled service without launching Installer. Removing the
helper continues to remove legacy files and any bundled registration.

Local builds retain automatic selection of the sole valid Apple Development
identity. Use `CODE_SIGN_IDENTITY=-` for a deliberate ad-hoc build. An explicitly
empty/unavailable identity fails before building. Apple Development signing is
not Developer ID distribution or notarization; its migration uninstall package
remains unsigned and requires the existing system authorization flow.

For Developer ID builds, both **Developer ID Application** and **Developer ID
Installer** identities with private keys are required, from the same team. Set
`CODE_SIGN_IDENTITY` to the Application identity's full Keychain name (or SHA-1)
and `INSTALLER_SIGN_IDENTITY` to the Installer identity's full Keychain name.
`KEYCHAIN_PATH` optionally limits the identity search. The Installer certificate
signs the retained migration uninstall package; the Application certificate signs
the helper, frameworks, app, and DMG. No WeatherKit entitlement is added to the app.

If `NOTARY_PROFILE` is explicitly supplied, the release path:

1. Signs, notarizes, staples, and assesses the migration uninstall package before
   the app seals its Resources directory.
2. Signs the app; notarizes its ZIP; staples and assesses the app before DMG staging.
3. Signs the DMG; notarizes, staples, and assesses it; then computes its SHA-256.

The standalone uninstall asset is copied from the already stapled package. This
order avoids modifying a sealed resource after app signing and supports offline
launch/install tickets. Without `NOTARY_PROFILE`, a signed build is still **not
notarized**. Actual certificate import, Apple's responses, and Gatekeeper behavior
must be verified after enrollment.

## Future GitHub Actions configuration

Use `.github/workflows/release.yml`, runner `macos-15`, Xcode `16.4`, Swift `6.1.2`.
Configure secrets only after obtaining the real credentials yourself:

| Repository secret | Contents |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | Base64 encoding of a password-protected P12 containing both Application and Installer certificates **and private keys** |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | That P12 export password |
| `APPSTORE_CONNECT_API_KEY_ID` | Notary API key ID |
| `APPSTORE_CONNECT_API_ISSUER_ID` | Its issuer UUID (team key) |
| `APPSTORE_CONNECT_API_PRIVATE_KEY` | Actual private P8 key contents, used only in runner temporary storage |

Use an App Store Connect **team** API key accepted by `notarytool`. The workflow
uses an isolated temporary signing Keychain, stores notary credentials there,
removes temporary P12/P8 files, and deletes the Keychain on completion/failure.
The P8 key is never copied into the app or an artifact. Sparkle publication still
requires its separate `SPARKLE_PRIVATE_KEY` secret and `SPARKLE_PUBLIC_KEY` variable.

Run a normal unsigned PR/dispatch preflight with `publish=false` and
`signed_validation=false`. It uses no Apple signing/notary credentials, even when
secrets exist. After credentials are ready, dispatch with `publish=false` and
`signed_validation=true` to exercise signing and Apple's notarization without
creating a GitHub Release, tag, or appcast update. Missing or incomplete required
configuration fails instead of falling back to ad-hoc. Keep version/build inputs
identical to the checked-out `Support/Info.plist` for either preflight.

Formal publication must run from `main` after review and the required Swift 6.1.2
preflight. Version and build changes, commits, pushes, workflow dispatch, and
publication still need the user's requested delivery scope; none happened here.
A signed/notarized validation performs uploads to Apple and should only be invoked
when the credentials and enrollment are ready.

## Weather service endpoint in the app

Apple's [macOS capability matrix](https://developer.apple.com/help/account/reference/supported-capabilities-macos)
marks WeatherKit unavailable for Developer ID distribution. Glance therefore uses
a separately operated WeatherKit REST backend, with the Shortcuts path retained.
The WeatherKit signing private key belongs exclusively in backend secret storage;
it must never be included in an app plist, entitlements, source, or CI artifact.
Developer ID signing does not itself make weather operational.

Set repository **variable** `WEATHER_SERVICE_URL` only after the separately prepared
backend is deployed and tested. For local app packaging, use the environment
variable of the same name. It is the complete public HTTPS `/v1/weather` endpoint.
The builder writes only that non-secret URL to `GlanceWeatherServiceURL` in the app.
No endpoint means no plist key, and native weather is unconfigured/Shortcuts remain
the default. The old `GlanceEnableWeatherKit` flag is not used.

Validation rejects HTTP, credentials, query strings, fragments, whitespace, other
paths/ports, local DNS suffixes, and nonglobal literal IP addresses. This is syntax
validation, not DNS resolution or proof of backend availability. DNS, rate limits,
backend authentication, WeatherKit entitlement/REST service permissions, quota,
privacy, and deployment remain separate operational checks. Local HTTPS endpoint
selection does not authorize deployment or spend.

Location authorization remains a macOS prompt. The app privacy strings explain
Wi-Fi details and the approximate location sent to the selected weather service.
No location authorization or real weather request is performed by helper tests.

## Offline checks performed by code

```bash
python3 scripts/test-signing-configuration.py
bash -n scripts/build-app.sh scripts/build-helper-packages.sh scripts/release.sh scripts/validate-signing-configuration.sh
swift test --filter 'MagSafeHelperStrategyTests|MagSafeInstallerWaiterTests'
```

The shell suite exercises real unsigned package generation and explicit invalid
configuration; its synthetic read-only identity inventory tests configuration
selection only, never Apple's certificate trust or credentials. Full `swift test`
and `swift build -c release` remain the repository acceptance checks. Before
merge/publication, run the required nonpublishing Xcode 16.4 workflow from the final
remote branch/commit.

Apple references:
[Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/),
[packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution),
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).

## Weather deployment and location lifecycle (2026-10-13)

The WeatherKit REST Worker is deployed on the existing Cloudflare Workers Free
plan at `https://glance-weather-service.pengyimm.workers.dev/v1/weather`. The
WeatherKit-only private key is stored in a restricted operator-side file and
Cloudflare encrypted Secrets; it is absent from the repository and app bundle.
A real public Sydney example request passed HTTP200, including current weather,
hourly/daily forecasts and official Apple attribution. Worker tests:20 passed.

The weather source menu now precedes the updated timestamp on the same row, with
a borderless caption style. Configured builds default to Apple weather; the
installed preference is nativeWeather. Location permission must be verified on the
real Mac. The location session now survives popover dismissal while awaiting
system consent, stops location updates on cancellation, and serializes replacement
requests so cancelled lookups cannot clear newer callbacks.31 focused Swift tests
passed, including immediate replacement and cancelled middle lookup cases. Local
Swift is newer than CI; the required Swift6.1 CI preflight remains pending.

Final location-fix app notarization submission:
`df2ed401-424d-4e05-9985-50b808c16b04`; preserved app at
`dist/notarization-weather-permission/Glance.app`. Apple Accepted, ticket
stapling/validation, strict codesign and Gatekeeper assessment passed. The exact
version was installed to `/Applications/Glance.app` and restarted. Real permission
and weather display verification remain separate from offline tests.

User-requested UI correction: the standalone Apple Weather/attribution rows were
removed from both summary and weather details. First-time weather authorization
now requires explicitly opening weather details; already authorized refreshes
remain available.32 focused Swift tests passed. App submission
`13b2466b-2757-4c4f-94f6-3a652534a706` was Accepted; ticket, signature and Gatekeeper
checks passed before replacing `/Applications/Glance.app` and restarting it.

City display correction: optional CoreLocation reverse geocoding now enriches the
shared weather result with a city/region name. It runs alongside weather, uses
coordinates rounded to two decimal places and the current locale, and stops after
four seconds or cancellation. Failed place lookup preserves the weather result.
The source menu now includes the localized Source prefix on the existing update
row.56 focused weather tests passed; local signed release build passed. Submission
`74b2e8ec-e2bd-4e7f-93ce-f4ad973f4fd4` was Accepted, with stapling, strict signature
and Gatekeeper checks passing before installing the preserved app from
`dist/notarization-weather-city/Glance.app`. Live city display remains a separate
UI check; Swift6.1 CI preflight remains pending before merging/publishing.
