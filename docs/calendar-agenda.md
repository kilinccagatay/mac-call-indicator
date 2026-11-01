# Optional macOS Calendar agenda

Calendar sharing is opt-in and independent of call detection. Use a calendar
already synced to macOS Calendar; no Microsoft Graph application, Entra app
registration or Exchange credentials are needed by Mac Call Indicator. Company
policy and the calendar provider still determine whether local access is allowed.

## Setup

1. Update the Home Assistant custom integration and restart Home Assistant once.
   Keep a backup of the previous integration and installed Mac app.
2. Open **Settings → Calendar → Allow Calendar access…** in the Mac app. Apple
   requires Full Calendar Access to read events; the app never writes events.
3. Choose the calendar that actually contains your work events. Its display name
   may be **Calendar** under an Exchange account; a calendar named **Work** can
   instead be an empty personal calendar. Verify an expected workday against the
   native Calendar app. The selected calendar identifier stays local to the Mac.
4. Use **Connect agenda to Home Assistant…**. Existing Home Assistant sign-in is
   reused, or the app opens the normal sign-in flow. Pairing requires a Home
   Assistant administrator. A separate status-only receiver is created; the
   existing call receiver and lamp configuration are preserved.
5. Enable agenda sharing and, optionally, scheduled meetings in the meeting
   indicator. Choose **Save calendar settings**. The optional advanced receiver
   field accepts a dedicated agenda webhook, stored in Keychain, never a token.
6. Subscribe the office dashboard to the displayed `sensor.mac_call_agenda_…`
   entity. Never subscribe the title-free Denver dashboard to that agenda sensor.

## What is displayed

The agenda carries three workdays: today's remaining timed events on weekdays,
followed by the next two workdays. Saturday and Sunday begin with Monday.
The office panel offers equal-width day tabs with an explicit selected state;
selecting another day shows only that day's events. The first day is restored
after a real display-dark notification, page hiding, or a new base workday.
All-day, cancelled, declined and explicitly free events are excluded. Public
holidays are not inferred. The compact office view shows two upcoming entries,
or three when its height permits; an accessible summary indicates more entries.
Each day is bounded to 16 title/time-only events. Local calendar change
notifications and the existing one-minute fallback refresh the whole window.
Future selected days never trigger the current meeting indicator.
Finished events leave the list automatically. A fresh empty calendar is different
from an unavailable calendar.

Calendar notifications invalidate the local cache; a one-minute fallback query
covers missed notifications and date changes. Reports are sent about every ten
seconds and expire after 90 seconds without a valid report. No daily-only polling
is used. The Mac must be awake, signed in and connected; the upstream provider
must first sync the invitation into macOS Calendar. Check Calendar → Settings →
Accounts → the work account → Refresh Calendars as well: a 15-minute upstream
sync interval can delay invitations regardless of the helper. Use Push where
reliable, or a one-minute interval if offered and permitted by the organization. This is a convenience display,
not a replacement for the calendar application's meeting alerts.

If scheduled indication is enabled, the existing boolean meeting report combines
actual call OR manual timer OR a currently active calendar event. Ending any one
source cannot cancel another. A Monday agenda shown on Saturday cannot activate
the indicator. A scheduled meeting can activate it even if you do not join.

## Privacy and failure behavior

Only bounded event titles and start/end times, the selected day's boundaries and
freshness timestamps enter the agenda channel. Participants, notes, locations,
join links, event IDs, calendar names and account addresses are excluded. Events
are not saved by the Mac app or printed in its diagnostics. The HA agenda entity
marks its event attribute as unrecorded. Titles are treated as text in the panel,
never HTML. The receiver accepts only local webhook requests and validates the
payload schema, body size, timestamp window and lease. Invalid reports cannot
extend a lease. Expiry removes the visible agenda rather than claiming no meetings.

The ordinary call webhook remains strictly boolean-only. Denver continues to
receive that boolean, without event names. If the Home Assistant connection is
HTTP, use only the trusted private LAN; it is not encrypted transport. Do not
publish webhook URLs, tokens, calendar data or real work screenshots.

## macOS permissions during development

Ad-hoc signed development builds may require Accessibility and Calendar approval
again when their executable changes. Preserve the installed app for rollback and
finish a build before requesting approval. A stable trusted signing identity is
needed for predictable approval across releases; do not weaken TCC or replace
its code requirement with an identifier-only rule. The Calendar permission does
not replace Accessibility permission used for actual Teams call detection.

## Validation

Automated tests cover independent meeting sources, time boundaries, weekend
selection, bounded title-only reports, strict Home Assistant validation, expiry,
separation from actuator policy, title escaping and empty/offline UI states.
Real calendar synchronization, real connected/ended calls and physical panel
regression remain installation acceptance checks; passing unit tests alone does
not establish end-to-end reliability.

![Example office agenda with synthetic meeting names](images/office-agenda-demo.jpg)

Synthetic example only: no real work calendar or printer job is shown.

## Three-day protocol compatibility

The original `day_start`, `day_end` and `events` continue to describe the first
workday. An optional `days` array contains exactly three ordered workday reports,
including that first day. The updated receiver accepts older single-day clients;
update the integration and restart HA before installing the new Mac build.
Both `events` and `days` are excluded from recorder history. No attendees,
locations, notes, identifiers or account details are added. The ordinary call
channel and Denver's title-free indicator remain unchanged.

Development build 8 adds this window. Installation preserved the existing
Accessibility approval on the tested Mac; ad-hoc builds can still require renewed
macOS approval on other installations.

![Three workday tabs with a selected Tuesday](images/three-workday-agenda.png)

Synthetic panel example with generic titles. On the tested installation, the
user renewed Calendar approval after the update and confirmed the calendar
returned. Accessibility approval remained valid. Native dark/reset behavior
was observed separately; this does not establish a complete device regression.
