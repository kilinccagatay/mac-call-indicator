# Computer activity and a companion panel

Mac Call Indicator reports computer availability independently of meetings:
`{"computer_active":true}` means the session is active, unlocked and its display
is awake. Locking, display sleep, system sleep or switching out of the session
reports `false`. Unlocking does not override a still-sleeping display, and waking
the display does not override a still-locked session.

The app uses macOS workspace display/sleep/session notifications, supplemented by
macOS lock/unlock distributed notifications and a boolean startup snapshot. The
lock notification names are system implementation details; verify lock/unlock on
your macOS version. No screen contents, input, usernames or session identifiers
are sent or logged. This feature needs no Accessibility, Calendar, camera,
microphone or screen-recording permission. Existing Teams detection still needs
Accessibility; optional agenda sharing still needs Calendar access.

State changes queue an immediate report; the ordinary ten-second heartbeat also
retries the current state. A final sleep report can be lost when networking stops;
receivers must expire the heartbeat. This is availability, not proof of shutdown:
app exit and a broken network can also stop reports.

## Home Assistant

Update the integration and reload its entry (or restart Home Assistant). The same
private webhook now accepts **either** the existing `in_call` boolean **or** the
new `computer_active` boolean in separate requests. Existing clients remain
compatible. Old integration versions can reject computer reports without breaking
the separately sent meeting reports.

The integration creates a second binary sensor named **Computer active**. Its
availability expires independently after 40 seconds. Computer reports do not
refresh meeting evidence, cancel a manual meeting, send agenda data or operate the
configured meeting lamp/switch. No output automation is enabled automatically.

For an existing YAML receiver, merge the updated
[example](../examples/home-assistant.yaml), preserving your private webhook secret
and other template items. It creates `binary_sensor.mac_computer_active`. Do not
keep the old unguarded timestamp template: a computer-only request must not count
as fresh meeting evidence.

## Samsung companion

The optional Samsung root display helper can consume the computer sensor with
`"computer_state": true` in its private configuration. It observes a fresh `off`
as inactive immediately rather than waiting two minutes for reports to disappear.
A fresh `on` wakes only a display the helper itself put to sleep. A missing report
still uses the configured stale threshold, normally 120 seconds; connection errors
retain the existing fail-open recovery.

The phone keeps its existing inactivity policy: it must reach zero brightness
before the helper requests Android display-off. Camera/proximity and manual power
controls remain available, so this is not a kiosk lockout and movement can keep the
phone active. The phone still needs CPU/network polling to wake when the Mac returns.
Denver's meeting badge and display policy are independent and unchanged.

## Permissions and rollback

Keep the installed app path, Keychain connection and preferences. Current source
builds use ad-hoc signing. A changed binary can require renewed macOS approval even
when the old Accessibility switch appears enabled. Remove only the stale app entry
and add the installed app again through normal System Settings; check Calendar
access too. Never edit the TCC database or disable macOS protections.

Keep a copy of the previous app and receiver configuration. Restore both to roll
back the new channel. For Samsung, restore its previous helper JAR and private
configuration, then restart only that helper. The Android APK does not need to
change for this feature.


## Validation record — 2026-11-02

- PASS: 22 Swift tests; 17 Home Assistant integration tests, including independent
  freshness and computer reports not changing a meeting lamp.
- PASS: installed local 0.4.1 build reports computer activity, and the actual
  running process confirms existing Accessibility and Calendar approvals.
- PASS (targeted physical test): Touch ID lock + Esc closes the Samsung display;
  unlocking reopens it without touching the phone. Device telemetry recorded
  Android Asleep / Display Power OFF and then return to ONLINE.
- PENDING: the final helper's availability-grace hardening has policy coverage;
  its real system-sleep cycle, cold-boot persistence and complete panel regression
  are not yet accepted. Existing intermittent manual power/idle behavior remains
  a separate investigation. This source update is not a new accepted release.
