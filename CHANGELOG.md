# Release notes

## 0.4.0-rc.1 — Optional local workday agenda (2026-11-01)

Universal macOS app version 0.4.0, build 7; Home Assistant integration version 0.4.0.
This is a pre-release from the calendar development branch. The installed local
app is not replaced by packaging or publication.

### Added

- Optional EventKit access to one selected calendar already synced to macOS.
- Today's remaining timed events; weekends show Monday. All-day, cancelled,
  declined and explicitly free entries are filtered; holidays are not inferred.
- Event-store change observation and a one-minute fallback query. New invitations
  must first reach macOS Calendar from the upstream account.
- Separate agenda receiver and sensor, with opt-in title/start/end sharing,
  approximately ten-second reports and a 90-second expiry.
- Optional scheduled meeting indication combined with actual calls and manual
  timers, without one source cancelling another.

### Preserved

- Default boolean-only call reports; no participants, phone numbers or messages.
- Manual 30-minute / one-hour meetings and visual end-time picker.
- Home Assistant sign-in / secure import, Keychain storage and output modes.
- Start at Login and the direct Accessibility Settings shortcut.
- Existing webhook receivers and lamp configurations need no migration for calls.

### Upgrade and limits

Update both the app and Home Assistant integration; restart HA before agenda pairing.
Calendar permission is optional. Accessibility is needed only for automatic Teams
detection, not manual timers or EventKit itself. Replacing an ad-hoc signed binary
can require renewing its Accessibility entry. Do not reset all macOS privacy settings.

The app is ad-hoc signed, not notarized. Apple Silicon and Intel slices are built;
physical Intel execution has not been tested. Calendar freshness cannot override
provider sync delays, a sleeping Mac or an offline connection. Now Playing/Plex
control is not part of this release. See the guides for remaining validation limits.

## 0.3.1

Direct shortcut from missing Accessibility status to the relevant macOS settings.

## 0.3.0

Home Assistant pairing, selectable output types, secure connection settings,
meeting-light blueprints, manual timers and universal release packaging.
