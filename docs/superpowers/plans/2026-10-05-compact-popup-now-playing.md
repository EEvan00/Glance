# Compact popup implementation plan

**Goal:** Implement the approved compact popup with Codex quota, capsule sliders, output submenu and playing-only media rows.
**Architecture:** SwiftUI consumes dedicated visible-panel controllers. Codex uses a short-lived native Process JSON-RPC client with a configurable 1–12 minute cache (default five minutes). A small first-party Objective-C MediaRemote bridge is loaded by system Perl, streams notifications only while the popup is open, and routes commands by serialized player path.
**Tech Stack:** Swift 6.1-compatible SwiftPM, SwiftUI/AppKit, CoreAudio, dynamically resolved DisplayServices and MediaRemote.
**Spec:** docs/superpowers/specs/2026-10-05-compact-popup-now-playing-design.md

## Global constraints
- macOS 15+, Xcode 16.4 / Swift 6.1.2 acceptance environment.
- No commit, push, PR or release without user authorization.
- No artwork, hidden-panel timers or media subprocesses. Quota reads follow the configurable interval; explicit visible-panel refresh bypasses cache without overlapping requests.
- Missing data is unavailable, never fabricated. Commands are tied to source identity.

## Tasks
- [x] Add tests for quota decoding/clamping/cache, playing-source filtering/progress and controller cancellation before implementation; run focused tests to establish missing features.
- [x] Implement bounded child-process transport, quota reader/controller, and brightness controller with finite/clamped values.
- [x] Build first-party media dynamic library and Perl resource. Resolve runtime selectors defensively, request metadata/state per client and stream state changes. Serialize source paths for targeted command routing. Add packaging and development library lookup.
- [x] Implement capsule slider, compact 2x2 summary, output submenu, quota detail, media rows; remove obsolete popup-order UI while preserving saved preferences.
- [x] Wire popup open/close lifecycle explicitly from StatusBarController (controllers cache data across hosting content replacement).
- [x] Run focused and full tests, release build, package app, inspect rendered UI and verify child-process cleanup. Document hardware/CI verification limits.

## Verification cases
Quota fixtures have usedPercent=9, windowDurationMins=10080, resetsAt=1791589513 and secondary=null; expected remaining=91 and exactly one seven-day window. Negative/excess usage clamps to 100/0, unknown windows remain missing. Closing during a pending read cancels the child and prevents late publication.
Media fixtures contain two distinct playing identities plus paused/stopped/empty-title entries; only playing valid rows survive, duplicate identities collapse, max two rows, stable ordering. Progress is clamped and invalid duration yields no progress. Command requests preserve exact identity.

## Latest verification
- Width reduced to 284pt with symmetric 12pt trailing-chevron layout and an expanded 20×28pt hit region that avoids slider overlap; shared arrows 11pt/28×24pt, aligned 22pt icon columns, concentric 12pt/8pt circular corners, icon-only footer and brighter secondary text without font-size changes.
- Single and dual sources retain draggable progress; dual rows have no divider. Paused sessions retain metadata and a play button; fully paused panels have no periodic progress timeline.
- Media routing now obtains the actual client player, validates resolved bundle/PID/player identifier during query and before commands, rejecting redirection. Seek gestures lock their original identity and reject disappeared/replaced sessions. Signed isolated dual-client exact seek assertions and pause/resume/exit checks pass after rebuilding the dylib.
- User reported intermittent Chrome+Music cross-source seek. This risk is guarded by full resolved-identity validation; the real Chrome+Music pair remains unverified by the agent. Do not claim isolated clients prove browser behavior.
- Final full suite: 350 XCTest tests and 14 Swift Testing cases passed. Native double-source preview: 300×277pt; temporary render fixture removed. Release build and app packaging are rerun for the final implementation. Physical display/audio changes, real popup mouse interaction, power measurement and Swift 6.1 CI remain unverified. No commit/push/release.


2026-10-05 后续调整：Codex 仅在每次打开弹窗或点击 Refresh now 时查询，无自动刷新定时器及间隔设置；关闭弹窗取消查询。弹窗顶部限制在菜单栏下沿及状态按钮下沿较低处（上移 1pt 后不再额外留缝），支持多屏坐标。
