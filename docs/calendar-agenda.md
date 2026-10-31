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
3. Choose one work calendar. The selection stays local to the Mac.
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

On weekdays the agenda contains today's remaining timed events, including a
meeting already in progress. Saturday and Sunday show Monday's agenda instead.
All-day, cancelled, declined and explicitly free events are excluded. Public
holidays are not inferred. The compact office view shows two upcoming entries,
or three when its height permits; an extra-count label indicates more entries.
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
