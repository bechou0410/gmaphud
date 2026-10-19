> Release 0.2.1 enables Waze alongside VietMap (one selected source only). Waze 5.25.0 ABI/UUID guards remain; GOFA4.2.1 build3 re-enabled experimentally; cold/locked GPS measured, current native limits held while stationary GPS is silent; red-light/no-right replay observed, long-idle/full alert coverage pending. Designed artwork replaces temporary Waze images. Cold mobile-only initialization supplied fresh native 0/60 to Full Map and Dashboard in device tests. Real-road speed, long-idle reliability and active alert coverage remain unverified. Published as 0.2.7.

# Common source output · v1

Implemented in internal **0.1.20**. This is the adapter/bridge contract for both
CarPlay and foreground Google Maps on iPhone. VietMap is the first migrated source.
The internal Waze adapter uses the same contract. Settings enables VietMap and experimental Waze; GOFA is experimental;
Waze support is experimental and build-sensitive. Each native entry point is checked on its own (selector and type encoding, or the limit getter's code with address fields masked, found once per build UUID), so builds other than the measured 5.25.0 keep what still matches; the native GPS start for a cold background launch stays 5.25.0-only.

The owning definitions are [source-output.h](../common/source-output.h),
[source-output.m](../common/source-output.m) and
[source-transport.h](../common/source-transport.h). Keep IDs stable; append new
alert types instead of reordering the enum. An incompatible encoding needs a new
schema version and notification namespace.

## Envelope

Adapters pass an immutable `NSDictionary` to `GVMPublishSourceOutput`. For example:

```json
{
  "schemaVersion": 1,
  "sourceID": 1,
  "speed": { "value": 42, "receivedAt": 100 },
  "speedLimit": { "value": 50, "receivedAt": 101 },
  "alerts": [
    { "type": 4, "value": 80, "distance": 200, "receivedAt": 101 },
    { "type": 30, "value": null, "distance": 400, "receivedAt": 102 }
  ]
}
```

The numbers above are illustrative receive times, not wall-clock dates. JSON here
documents the shape; IPC carries numeric states, not JSON or images.

| Field | Rule |
| --- | --- |
| `schemaVersion` | Integer `1`; unsupported schemas reject the envelope. |
| `sourceID` | Integer 1–7. `1` is VietMap, `2` is Waze, `3` is GOFA; 4–7 are unassigned. |
| `speed` | Optional sample, integer 0–400 **km/h**. Stationary zero is valid. |
| `speedLimit` | Optional sample, integer 1–400 **km/h**. Zero means unavailable. |
| sample `receivedAt` | Original `NSProcessInfo.systemUptime` in seconds on the same device/boot. |
| `alerts` | Required array; normalization keeps at most two fresh distinct alerts. Empty clears all alerts. Input is bounded to 64 entries. |
| alert `type` | Stable semantic `GVMRoadAlertType`, independent of an app's image index. |
| alert `value` | Integer 1–400 km/h for `GVMRoadAlertSpeedLimit`; otherwise null. |
| alert `distance` | Integer 0–10000 **metres**, or null when unknown. Zero means at the point. |
| alert `artworkID` | Legacy optional decoration ID, integer 0–127; defaults to 0. Ignored by the bubble renderer. |
| alert `receivedAt` | Original receive time of that alert update; independent of scalar fields. |
| `lanes` | Optional lane set for the next junction: `{distance, items, receivedAt}`. Expires at five seconds like the other fields. A malformed set is omitted whole. |
| lanes `distance` | Integer 0–10000 **metres** to the junction, or null when unknown. |
| lanes (VietMap) | While VietMap counts down to a junction (`updateLaneInfo` on `vml_main_channel`, `{distance, laneItems:[{enabled, imageId}]}`, about every two seconds), its lanes with that distance; the direction comes from `imageId` (`lane_<directions>_<to follow>`, VietMap's names such as STRAIGHT, SLIGHT_RIGHT, UTURN_LEFT joined by "-"). Otherwise the lanes VietMap Live shows: its overlay `laneInfo`, in effect on the stretch being driven, with a null distance. VietMap changes or clears both itself (a patch without `laneInfo` leaves them; a countdown without lanes, or one that cannot be read because its distance is missing or no lane direction is recognised, ends it; a countdown not renewed for six seconds lapses), so the adapter keeps them as they stand and publishes them with the publication time; if VietMap Live stops publishing, they expire at five seconds. |
| lanes (GOFA) | GOFA's lane board ahead (`notificationLaneBoards` › `pushLaneBoardsValue`, a `GOFA.DatapointModel` whose `metadata.detail_lanes` lists the lanes left to right separated by "|", each lane's OSM `turn:lanes` directions separated by ";"), posted about once a second with or without a route. Published with the distance from GOFA's latest GPS fix to the board until the board is reached (5 m), GOFA posts none, or no board arrives for three seconds. No lane to follow is given. |
| lanes (VietMap limits) | Its overlay `laneSpeedLimits` (`[Int]`, one per lane, left to right), kept like `laneInfo` (a patch without it leaves it; a replacing patch without it clears it; an update with a non-integer element is ignored, as VietMap's CarPlay plugin ignores it; a whole number beyond -255...255 clears it). They go with the lanes in effect when both count the same lanes, or alone, on lanes without a direction, when there are no arrows; not with an advance countdown. |
| lanes `items` | 1–12 lanes, left to right. Each is `{code, enabled, limit}`: `code` uses VietMap's direction bitmask (1 straight, 4 right, 16 U-turn left, 64 left, 256 U-turn right; other bits are dropped), `enabled` is a boolean and defaults to true, and the optional `limit` is the lane's speed limit sign as VietMap gives it (an integer from -255 to 255: a limit in km/h, 0 or -1 a sign without a number, -2 or less a sign VietMap draws grey); every lane has one or none does, else the limits are left out. The New UI strip drops the limit row before its arrows when space is short. |

Missing, null, invalid or expired scalar samples are omitted. Invalid individual
alerts are omitted; malformed envelopes/containers are rejected. Numeric strings,
booleans, fractional values, nonfinite values and out-of-range numbers are not
coerced. Adapters convert native units and rounding before this boundary. Unknown
fields are stripped; coordinates, routes and raw app payloads do not leave it.

Each field expires at **five seconds**, independently, and future timestamps are
rejected. Publication, polling and refresh requests never renew receive times. The Waze adapter
is the one exception, described below: its live limit is a new reading each second, and it
renews the receive time of a stationary speed.
IPC floors times to milliseconds, so expiry may be up to 1 ms earlier. No valid
limit means no near-limit/overspeed comparison; existing placeholders remain.

Alerts sort by nearest known distance, then newer receive time. Unknown distances
follow known distances. Identical type/value/distance entries are deduplicated;
the newer wins. Only the first two survive. Supported semantic categories include
cameras, upcoming speed limits, residential boundaries, passing/turn restrictions,
mandatory directions, railway, tunnel, toll and rest-area warnings. Exact numeric
IDs and names are defined by the enum and `GVMRoadAlertName` in the owning files.

## One selected source

VietMap is the default. Consumers call `GVMReadSourceOutput(now)` and use its entire
envelope; they do not independently combine speed, limit or alerts from adapters.
Only the selected adapter can publish. Missing data stays missing; sources are never
merged. Auto-wake runs only for the selected source when enabled and the visible-host
lease and existing location permission permit it. After five failed wakes the
SpringBoard supervisor selects the next installed source with location permission
(VietMap, GOFA, Waze) through `GVMSelectOutputSourceForNow`, which advances the epoch
without saving; the next Google Maps session restores the saved choice with
`GVMRestoreOutputSelection`. Only SpringBoard restores at start, so CarPlayApp starting on
a connection does not undo a fallback.

`GVMSelectOutputSource` persists the single ID and advances a selection epoch.
Switching source immediately makes the old frame unreadable. Returning to a
previous source also needs a new frame, even if its values have not changed.
`GVMRestoreOutputSelection` restores the saved ID from SpringBoard. Settings enables VietMap and Waze. GOFA is enabled experimentally; its saved selection is restored in a distinct source epoch.

`GVMRequestSelectedSource` posts only the selected provider's request name, returned
by `GVMOutputRequestName`. The running provider checks selection again and replies
with a forced publication of its original samples. Requests do not create data or
start an app; the existing opt-in background supervisor owns that separate task.
The VietMap response retains its existing two-second throttle.

## Numeric IPC

Each source owns thirteen Darwin states at
`com.chou.gmaphud.output.v1.<sourceID>.<slot>`:

| Slot | Content |
| --- | --- |
| `commit` | Revision in upper bits, schema version in low byte. Odd revision means writing; positive even revision means committed. |
| `selection` | Selection epoch belonging to this frame. |
| `speed`, `limit` | Existing scalar numeric encoding and original timestamps. |
| `alert.first`, `alert.second` | Original timestamp, source ID, **semantic type**, distance. |
| `alert.first.value`, `alert.second.value` | Artwork ID plus optional numeric alert value. |
| `lanes` | Original timestamp, lane count and distance (16383 when unknown); zero when there are no lanes. |
| `lanes.first`, `lanes.second` | One byte per lane, eight lanes to a word: five direction bits and the enabled bit. |
| `lanes.limits.first`, `lanes.limits.second` | Per-lane speed limit signs, ten bits per lane and six lanes to a word: present, dimmed, then the number shown (0 for a sign without one). Every lane of the set or none; zero when there are none. |

The writer begins an odd revision, writes selection and all eleven payload words,
then finishes an even revision. The reader checks commit and selection before and
after; partial writes, source switches, old epochs and unknown schemas are
unavailable. Each source has **one adapter writer process**; local operations are
serialized. This is a consistency protocol, not cross-process writer arbitration
or cryptographic authentication. Other injected/privileged software can still
alter Darwin state. There is no network service, GPS feed or authorization change.

After each committed frame that changed, the writer posts
`com.chou.gmaphud.output.v1.<sourceID>.changed`. `GVMObserveSourceOutput` delivers
those posts and selection changes, so Google Maps refreshes at once (coalesced to
10 Hz); its 0.5 s poll remains for expiry. `GVMObserveSelection` delivers selection
changes alone.

Live production uses this versioned namespace exclusively. Existing bounded
`gvm-test-speed` display samples keep their old test channels and are translated
at the Google Maps test boundary; they never enter the live source namespace.
Old production channels are not a fallback. Loading 0.1.20 requires both apps to
reopen and a respring to load the matching SpringBoard component; mixed loaded
versions will not bridge. No device restart/installation is performed by host tests.

## Adding an adapter

1. Allocate an unused stable source ID and add its display identity. Implement the
   actual app callbacks; do not synthesize missing production data.
2. Convert native units to km/h/metres, map alerts to semantic types, and preserve
   independent receive times. Build/normalize with `GVMSourceOutput`.
3. Publish using `GVMPublishSourceOutput`, handle only that source's request name,
   and send empty fields/alerts when cleared. Do not revive stale caches.
4. Keep app payload parsing/artwork recognition in the adapter. The VietMap example
   is [vietmap-output.m](../provider/vietmap-output.m); the renderer uses semantic
   types and optional decoration, not VietMap indices as alert identities. Missing
   artwork uses a generic camera/warning or a numeric speed sign.
5. Test real callbacks, unit conversion, expiry, invalidation, source switching and
   both Google Maps surfaces before enabling that source in Settings.

## Verification

Run `sh test-source-output.sh` for contract, all 46 VietMap mappings, actual
`VMNavSource` migration, frame validation and isolated real Darwin IPC checks,
including a separate reader process. Run `sh test.sh` for the full regression suite
and `sh build-tweak.sh all` for both package schemes. Host IPC tests use a unique
notification/preferences namespace and remove their saved preference afterward.
The test executable requires that private namespace at compile time.

The matching 0.1.20 modules were installed and tested on iPhone 11 / iOS 18.6.2:
stationary speed/limit, simulated-location movement and upcoming-limit delivery
worked on native CarPlay and Google Maps iPhone; independent expiry and recovery
were checked. Camera rendering was tested separately with bounded display data.
This does not establish real-road accuracy, every alert kind or compatibility
with other devices, OS releases or app versions.

## Shared display icons

All sources provide semantic `type`, numeric `value` when applicable, `distance` and original `receivedAt`. Providers identify their own images internally and never choose display paths. The renderer uses `GVMRoadAlertIconName` in `common/source-output.m` to select the shared set in `tweak/layout/usr/share/gmaphud/gmaphud`. Current and upcoming limits use the same `speed_limit_<value>.png`; values without an icon keep a condensed semibold numeric fallback. Source IDs select data, not artwork. Existing wire schema/enum IDs remain unchanged; legacy artwork IDs are still accepted for compatibility. VietMap now omits that field.

## Waze adapter (internal trial)

`provider/waze-output.m` retains the measured `statsType=10`, subtype `1`,
trait `0`, `icon_alerter_cam_red_light` tuple to appended semantic type 34
(`GVMRoadAlertRedLightCamera`). Native valid descriptors are available before
Waze presents its warning card; trigger distance is not a freshness/validity gate.
Passed/invalid updates remove only their identity. IDs and raw payloads stay local.
Shared traffic-camera artwork represents this warning. Unknown tuples are omitted.

`WSVLocationGPSPosition` supplies mm/s converted to rounded km/h, preserving GPS
sample age and rejecting duplicates/future/stale timestamps. The optional native
limit getter is guarded by the measured executable UUID and entry bytes. After Waze
has processed its first GPS position, the adapter also re-reads that live native limit
every second, because iOS may deliver no GPS while the phone is stationary and Waze
still holds its current limit (VietMap's engine likewise re-sends its limit). A read
without a limit clears it. Speed follows the same reasoning for a stationary phone only: while
the latest GPS sample shows below 3 km/h (0–2 after rounding), that speed is re-published each
second with a renewed receive time until the next sample, for at most ten minutes after it by
both the uptime and the wall clock (uptime stops while the phone sleeps). The hold ends when
Waze's navigation GPS stops or restarts, and when a newer sample arrives too late to publish. In the background iOS delivered Waze a stationary
phone's GPS every 6 s to more than four minutes (2026-10-19, indoors), so a speed that expires
after five seconds was missing most of the time, while VietMap's engine re-sends its own; a
moving phone gets about one sample a second. A moving speed is never held and still lapses five
seconds after its sample, so a lost signal while driving shows no speed rather than an old one.
Missing limit support does not disable camera or speed data. Its build-specific semantics
still require wider device validation; nonzero speed was checked in the background on a
simulated drive whose positions carried a speed (60 km/h each second, then lapsing five seconds
after the drive ended).

The adapter publishes complete source-2 frames and answers only its request name
without renewing timestamps. Opt-in Waze wake now initializes the measured mobile
navigation GPS path while the selected-source lease is valid, without activating
any Waze CarPlay scene or changing authorization. Native start/stop entry points
are guarded by executable UUID and instruction bytes. Lease-owned GPS is stopped
through Waze's matching native stop path; genuine Waze foreground use takes ownership.
Only the navigation manager is forced to run, not the significant-change monitor.
The activity session precedes cold GPS start. A cached-only cold start can retry
its lease-owned GPS twice, after30s then60s; a GPS sample received after the
start ends retries; a held stationary speed does not. The next lease receives a fresh retry budget. No sample timestamp
is renewed by recovery. A locked-device real-GPS run delivered fresh data for
more than one minute; long-idle/driving coverage remains experimental.
Version/ABI mismatch leaves affected data unavailable.
Foreground and new background red-light activation/pass were measured on Waze
5.25.0 using a simulated route with Google Maps CarPlay. This does not establish
long-duration background reliability or real-road accuracy.

### Waze semantic inventory

The adapter writes `tmp/gmaphud-waze-alert-catalog.json` in the Waze sandbox. It retains at most64 observed type/subtype/trait/icon tuples with validity, passed state, bounded distance, app state and monotonic time. Only semantic/lifecycle changes schedule an atomic write, coalesced over one second. It does not store raw identities, locations or titles and does not change output freshness. This is diagnostic evidence; unsupported tuples are still excluded from output. Static artwork names alone must never enable a runtime mapping.

### Temporary artwork trial (0.1.23, unpublished)

GOFA source 3 is also an internal trial. Its contract is described below; it uses
the existing shared semantic artwork without adding GOFA-specific image paths.

Shared semantic IDs35–88 are appended for the missing road-warning families, with temporary original Waze PNGs in the existing common artwork directory. Existing IDs and schema/wire layout are unchanged. Other providers use the same semantic-to-artwork lookup. Exact known descriptor icon names map to these semantics experimentally; substring guesses and `_hidden` aliases are rejected. The red-light10/1/0 tuple retains its measured guard. Other mappings are asset-name-derived and must be compared with native warnings before release. Validity, passed status, distance bounds and original5-second freshness remain required. Seven compiled-only reference groups lack extracted PNGs and remain unavailable. Missing world speed-limit PNGs5/15/25/35/45 also use temporary Waze artwork; unsupported numeric limits retain the numeric fallback.

## GOFA adapter (internal trial)

Source 3 supports GOFA 4.2.1, version code 3 (`com.lumi.GOFA`). The adapter observes
`notificationSpeedBoard`, `notificationNextBoard` and `notificationOtherBoard`.
[The Swift parser](../provider/gofa-payload.swift) reflects only measured
`GOFA.SpeedBoardModel` and `GOFA.DatapointModel` fields. Next/other groups retain
separate original receive times and clear independently. Unknown models and signs
are rejected. Candidate coordinates and identities stay in the GOFA process.

[The source](../tweak/gofa-source.m) converts GOFA GPS input from m/s to km/h,
using the original date and rejecting duplicate, reordered, future and stale
samples. It excludes GOFA's own displayed-speed adjustment. Current limit comes
from the latest native `notificationSpeedBoard` `currentAllowSpeed`. GOFA re-issues that board only as its pipeline accepts movement, while its own map keeps showing it. GOFA re-issued boards every 5–9 seconds while nearly stationary in background, and none while iOS delivered no GPS. The adapter therefore re-asserts the latest board every second until GOFA replaces or clears it, or the latest GPS lies more than 50 m from the latest fresh position known when the board was processed (or the first fresh fix within the board's own five-second TTL); a board without such a position expires after five seconds. This works after a cold background launch, which creates no GOFA view model. Empty, unknown or zero native boards clear the limit, and stale GPS cannot renew it. Distances use `CLLocation.distanceFromLocation`, the same
operation verified in GOFA's native `DatapointModel.distanceToLocation`.
Alerts require fresh GPS and fresh candidate membership; polling/movement never
renew an old candidate list. Native removal, empty lists, very close points and
five-second expiration clear warnings. GOFA remembers identities reached within the existing5m exclusion while their fresh native membership persists; crossing to a larger distance cannot resurrect the same point. Removal/expiry releases suppression, and another approach can be observed. Only the speed board uses the position bound above; warning membership keeps its original receive time and is never renewed by GPS.

Sixteen existing semantics have enum-backed mappings: camera speed/traffic/red-light/AI,
residential start/end, toll, no-passing start/end, rest area and six turn restrictions.
Red-light and no-right output/rendering were measured during replay. Parking/stopping restrictions
and unverified upcoming numeric-limit IDs remain unavailable. This does not
establish every warning family or physical-road accuracy.

Selecting GOFA opts into continuing its already-running GPS while Google Maps is
visible. The shared location-session helper uses existing authorized When In Use
or Always access, a fresh host heartbeat and native background-location indication.
It respects GOFA's stop requests, restores original manager settings when the
source changes or visibility expires, and invalidates its temporary activity.
A two-second timer checks lease cleanup even without GPS callbacks, while the app
can execute. It never requests permission or cold-launches GOFA. Reopening GOFA
can be required after switching away/suspension; source switching still invalidates
old frames immediately.

The DuoDash workspace records device checks in `plans/261014-0230-gofa-source/results.md`.
GOFA's diagnostic `tmp/gmaphud-gofa-output.json` contains sanitized output, app state,
authorization, background-location flag and GPS age, without coordinates.

## Selected-source background lifecycle

The SpringBoard supervisor owns one selected app lease. The timed location-session
signal must also match the separate location-source ID and current selection.
Switching sources clears both signals before managing the next app. The provider
starts only its measured primary GPS delegate when needed; ending the lease stops
only starts owned by the feature and restores temporary manager flags.

While a Google Maps heartbeat is fresh, a selected source that is not running is
launched suspended at most every 3 seconds. A failed launch or a process that ends
before it is proven counts as a failed attempt; launches FrontBoard refuses because
the phone is locked are not counted. A wake is proven by a process alive for 10
seconds with output sampled after it started (`GVMWakeProven`), so the last frame of
a crashed process never resets the count. Five failed attempts, the fifth also given
its 3 seconds (`GVMWakeSwitchDue`), select the fallback above. When no usable source
is left, launches stop until the next Google Maps session and the saved choice is live
again; a selected source that is running (one the user opened) keeps its lease. The supervisor closes only a process that appeared within 15 seconds of its own
launch request (`GVMWakeOwnsProcess`) and has not been on a screen since: when the
selection changes, and when Google Maps has been gone for 10 seconds. Each source
app posts its pid to `com.chou.gmaphud.background.shown.<sourceID>` when one of its
scenes enters the foreground, because SpringBoard's process state does not count a
CarPlay scene as foreground. A Google Maps heartbeat that resumes after a gap is
also posted, and the supervisor handles it, a shown source and a selection change at
once; otherwise it ticks every second while a map, a countdown or a wake is active
and every five seconds when idle.

The main preferences menu exposes the source as a dropdown plus `autoWake` and
`autoExit` switches. Auto-exit observes real `CARSessionStatus` connection changes,
waits at least 20 seconds, and terminates only the tracked PID if it still matches.
Reconnection cancels the countdown. Google Maps visible on the iPhone is still in use:
it defers the countdown until the phone map is hidden and may wake a source that
auto-exit closed. The phone heartbeat expires after 12 seconds instead of being
cleared on brief inactivity, so a banner or app switch does not end the session. Waze cold CarPlay initialization is owned by the guarded
CarPlay relay, not by an output refresh. It preserves native samples and restores
the previous display after three seconds unless the user changes apps.

## Trial source availability gate

`GVMSourceEnabled` permits VietMap (1) and Waze (2) in trial 0.2.1. GOFA (3) remains unavailable; saved GOFA selection migrates to VietMap through a new selection epoch. Only the selected source may publish or respond to refresh requests.

The package includes WazeGMapHUDSource but omits GOFA and the CarPlay bootstrap companion. Waze uses the SpringBoard suspended mobile launch and selected-source background location session. No provider requests a native Waze CarPlay scene. Cold-start data and Dashboard ownership must be verified on device after this change.
