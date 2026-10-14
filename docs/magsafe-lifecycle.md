# MagSafe lifecycle and removal

MagSafe LED control runs in the signed, bundled helper. The public ad-hoc build
still uses its existing administrator-authorized legacy installer. Neither path
runs the Glance UI as root.

## Safety behaviour

- A successful or potentially partial LED-off write creates a 30-second lease.
- Glance renews every 5 seconds while it is running at its original bundle
  location. Renewal does not write the SMC. A lost lease requires an explicit
  off write before it can be renewed again.
- The helper checks expiry every 2 seconds, independently of the UI. After client
  exit/crash, the last lease expires and the helper restores system LED control.
  Failed restoration is retried; the helper must not idle-exit with pending
  restoration. Successful restoration is logged.
- Normal quit requests immediate restoration. Forced quit relies on lease expiry.
- Moving or replacing the original app directory stops renewal. Launching from
  `.Trash` or `.Trashes` never starts an off lease. The app tries to restore and
  unregister its bundled service; failure does not resume renewal.
- SIGTERM seals the helper against new commands before restoration. SIGKILL,
  kernel failure, and unavailable hardware cannot execute a cleanup guarantee.
- User LED preference survives normal quit and drag-to-Trash, so a reinstall can
  restore the requested setting. Explicit removal clears helper auto-recovery
  opt-in.

## Registration and upgrades

Certificate-backed builds use `BUNDLE_ID.MagSafeLEDHelper.TEAM_ID` as the stable
launchd label and preserve `BUNDLE_ID.MagSafeHelper` as the Mach endpoint. Team ID
comes from the signed helper binary, not the certificate display name. The build
also includes an unregistered historical descriptor for the old unscoped label.

Existing enabled registration or recorded opt-in allows one recovery attempt per
app launch: unregister the historical/current bundled registration, register the
current service, and apply the saved preference. System approval remains required
when macOS requests it. A fresh install does not automatically enable the helper.
Legacy privileged package files are not silently migrated; their existing
administrator-authorized removal flow remains explicit.

The in-app uninstaller pauses renewal/recovery, attempts restoration, removes
services, then moves Glance to Trash. Unresponsive IPC does not prevent service
removal. Errors removing services still stop the uninstall sequence.

Unregistering a service does not promise deletion of historical BTM database
records. Do not reset all background items or edit Apple's database to clear one
Glance record.

## Verification

Automated tests cover lease expiry/renewal, partial write failure, restoration
retry, terminal shutdown, bundle move/replacement/Trash detection, saved opt-in,
historical migration eligibility, bounded recovery, and uninstall gating.

Hardware validation must separately exercise normal quit, forced quit, moving a
running app to Trash, and reinstall. Check actual helper startup and successful
restoration logs; successful compilation alone does not prove LED behaviour.

### Local validation, 2026-10-14

- 556 XCTest + 19 Swift Testing tests passed; release build and signed app
  packaging passed on Apple Swift 6.2.4. The 22 signing/label script tests passed.
- Negative control: disabling lease-expiry restoration made the lost-client
  regression fail; normal source was restored and the full suite passed again.
- Killed the app process with SIGKILL while off; helper logged successful SMC
  system restoration approximately 30 seconds later.
- Moved the running signed application to Trash with FileManager: current launchd
  service was removed. Restored the app to Applications and launched it: helper
  automatically registered/runs again and the saved off preference remained.
- Recreated the historical unscoped label's EX_CONFIG failure, then upgraded with
  the new opt-in key absent: the historical descriptor successfully located and
  unregistered the old service, and the team-scoped service started automatically.
- Live testing caught a Dispatch callback actor-inference crash absent from unit
  tests; explicit @Sendable watchdog/termination handlers fixed the crash.
- Physical LED appearance was not observed by automation. Firmware acceptance
  and service state/logs are the hardware evidence. Normal UI quit is unit-covered;
  the live crash and Trash flows were exercised as above.
- CI Swift 6.1.2 preflight remains required before merge/publication; no remote
  commit, merge, release or notarization was performed for this change.
