# GMapHUD

**English** · [Tiếng Việt](README.vi.md)

Rootful/rootless iOS tweak that displays **speed, limits and road alerts from VietMap Live, Waze or GOFA in Google Maps on CarPlay and iPhone**. Inspired by the traffic bubble feature in DuoDash and TrueDash. Google Maps continues to handle navigation.

**Author: chou · AI-assisted with Codex.** chou leads, tests and publishes this independent community project; Codex provided AI development assistance. This credit does not imply that OpenAI is the publisher, copyright holder, maintainer or support provider. Not affiliated with or endorsed by VietMap, Google, Apple or OpenAI.

> Experimental software for stationary testing and research. It is not a certified driving aid. Displayed information may be wrong, unavailable or delayed. Follow actual signs, road conditions and applicable law. Read [DISCLAIMER.md](DISCLAIMER.md) before use; a disclaimer does not guarantee legal protection.

## Warning sources

Select **VietMap Live**, **Waze** or **GOFA**. Only one source is used at a time. Waze is read through checks on each native entry point, measured on 5.25.0: other builds keep speed, limit and alerts as far as their code still matches, and only 5.25.0 starts Waze GPS from a cold background launch (otherwise open Waze once). GOFA targets 4.2.1 build 3.

## Bubble placement previews

These are the same CarPlay preview images shown in Settings. They illustrate all supported placements; the displayed values and alerts are examples, not a claim of live-road accuracy.

| Full map · top left | Full map · top right |
| --- | --- |
| ![Full-map bubble at top left](docs/screenshots/full-map-top-left.png) | ![Full-map bubble at top right](docs/screenshots/full-map-top-right.png) |

| Full map · bottom left | Full map · bottom right |
| --- | --- |
| ![Full-map bubble at bottom left](docs/screenshots/full-map-bottom-left.png) | ![Full-map bubble at bottom right](docs/screenshots/full-map-bottom-right.png) |

| Dashboard · left | Dashboard · right |
| --- | --- |
| ![Dashboard bubble at left](docs/screenshots/dashboard-left.png) | ![Dashboard bubble at right](docs/screenshots/dashboard-right.png) |

## Features

Choose the bubble style in Settings → GMapHUD → Giao diện. **Classic** (default) keeps the familiar bubble. **New UI (beta)** combines speed and the limit badge in one dial whose ring fills toward the limit and turns amber near it and red above it, with a source tag under the dial and large alert signs whose distance tag fills as you approach. Both styles share the road-sign artwork: QCVN 41:2024 shapes and colours in a flat cartoon style; camera and traffic-police alerts use a white sign with the red ring of the speed limit and a corner badge for the camera type; other app-only reports use round tokens. The bubble supports horizontal/vertical layouts and lets you reorder modules. Sizes run from 50% to 250%; on New UI (beta), when the chosen layout has no room for the alerts at a large size, they move into a row under the dial so the dial keeps its size and place. New UI (beta) also shows VietMap's lane sign: one arrow per lane, left to right, under or over the bubble in a horizontal layout and beside the dial in a vertical one. It appears as soon as VietMap starts counting down to a junction, with the distance in a tag, and then stays without a distance for as long as VietMap Live shows the lanes in effect. With GOFA, the lanes of the lane sign GOFA reports ahead show with the distance to it until it is reached. Where VietMap Live gives a speed limit for each lane (on expressways, for example), each lane's sign sits under its arrow, or the signs stand alone when VietMap shows no arrows; VietMap's negative values are drawn grey, as VietMap draws them, and "--" is a sign without a number. In Settings, Vòng lớn makes the large circle the speed limit sign and the small one the current speed. While Google Maps navigates on the CarPlay full map, signs in effect and the lanes move under CarPlay's maneuver card, between it and the arrival times, and the bubble keeps the dial and the signs ahead; whatever does not fit there stays in the bubble. GMapHUDGuidanceRelay, loaded into CarPlayTemplateUIHost, only reads where CarPlay draws that column. Reopen VietMap Live after installing an update so its lanes reach Google Maps. Adjust size and placement separately for Full Map, Dashboard and iPhone. Recognized source alerts include distance and use up to two warning modules. Optional overspeed warnings illuminate the map or entire CarPlay screen.


- Full-map speed pill and compact vertical Dashboard card; light/dark map colors.
- Current speed remains visible, with `--` when unavailable. Missing limits show a dashed sign.
- Amber from 5 km/h below the limit through the limit; red above it. Visual cues only, no audible alert system.
- Card placement follows the map toolbar's safe area. The Google CarPlay heading/compass control is hidden.
- Speed and limit expire independently after five seconds. A heartbeat does not make old data fresh; Waze and GOFA re-assert only their app's current native limit while the phone is stationary.
- Optional stationary display test with a TEST badge and automatic expiry.


## Compatibility

| Component | Verified target |
| --- | --- |
| Device / OS | iPhone 11, iOS 18.6.2, rootless jailbreak |
| Google Maps | 26.40.3 |
| VietMap Live | 3.4.3 |
| Package | `com.chou.googlemaps.vietmap` 0.2.6, arm64/arm64e |

From 0.1.13, Google Maps is not restricted by version or executable UUID. Required private classes and method signatures are still checked; passing these checks does not guarantee compatibility with every release. The package identifier remains unchanged. Release 0.1.20 introduces a versioned production notification namespace; bounded display-test channels retain their original names.

From 0.1.13, the VietMap source also has no version restriction. Flutter channel structure and incoming data validation remain enabled. New app versions still require on-device verification.

UI states were checked using a real phone connected to Apple's CarPlay Simulator: normal, near-limit, overspeed and Dashboard. Live stationary values and simulated-location movement were observed. Physical-road accuracy, broad vehicle/head-unit compatibility and reliable background operation across OS/app updates are not established. VietMap display values are interpreted as km/h; simulated playback showed app-side differences from selected playback speed. This is not calibrated instrumentation.

## Install and remove

1. Use a compatible jailbreak and legitimately installed apps with any required VietMap entitlement/subscription. These are not supplied here.
2. Copy **https://gmaphud.caidat.app/** into **Sileo → Sources → +** or **Zebra → Sources → +**, refresh, then search for **GMapHUD**. The [source page](https://gmaphud.caidat.app/) has quick-add buttons for both. Alternatively, download the `.deb` from [Releases](https://github.com/bechou0410/gmaphud/releases), and verify its SHA-256 against `SHA256SUMS`. The [original GitHub Pages source](https://bechou0410.github.io/gmaphud/) remains available as a fallback; downloads through it are not counted.
3. Install through your jailbreak's package manager. Review removal prompts for old bridge/probe packages listed in [tweak/control](tweak/control). This package does not uninstall vendor TrueDash. The source includes rootless (`iphoneos-arm64`) and rootful (`iphoneos-arm`) packages. Rootful still requires device testing on iOS 14; older app builds may need additional integration changes.
4. Close and reopen VietMap and Google Maps, then open Google Maps in CarPlay. Keep VietMap's background alerts running. A Live Activity alone does not prove fresh speed samples.

No default SSH password is provided or required. After updating, respring once to load the background component, then reopen Google Maps and Settings. Optional automatic wake supports When In Use or Always location access; enable VietMap alerts first.

To remove: uninstall `com.chou.googlemaps.vietmap` through the package manager, then close and reopen both apps. Removing files does not unload an injected library from an already-running process.

## Build and test

Requires macOS with Python 3.9+, Xcode command-line tools, Theos, a rootless-capable toolchain and an iPhoneOS 16.5 SDK obtained under its applicable license. SDKs and dependencies are not bundled.

```sh
git clone https://github.com/bechou0410/gmaphud.git
cd gmaphud
sh test.sh
THEOS="$HOME/theos" sh build-tweak.sh all
```

Packages appear in `packages/`. Both scripts use disposable directories and support spaces in the checkout path. The tested toolchain emits a pre-existing `-multiply_defined is obsolete` linker warning.

Build/test commands keep full logs locally and return a compact result with fixed diagnostic labels, preserving the command's exit code. No AI or external API is called. See [build/test reports](docs/build-triage.md) for local reports and the `GMAPHUD_CHECK_RAW=1` option.

## Maintain the Sileo source

Version policy: keep one next version throughout each unpublished development cycle, including every edit, build, and test installation. If the published version is `0.1.13`, all trial builds use `0.1.14`, and the release publishes that same `0.1.14`. Only after publication does the next development cycle use `0.1.15`. Do not increment the version for each trial. Use a commit hash or checksum to distinguish internal builds sharing a version; never overwrite a published package.

The [static source](https://bechou0410.github.io/gmaphud/) is published by GitHub Pages from `main` → `/docs`. [build-repo.py](build-repo.py) owns package/index/site generation, including the bilingual native Sileo depiction, CarPlay screenshot carousel, and changelog tab; [repo-template.html](repo-template.html) owns the shared landing-page layout and [repo-locales.json](repo-locales.json) owns its Vietnamese/English copy. The default page is Vietnamese; [en.html](https://gmaphud.caidat.app/en.html) is English. GitHub repository Settings → Pages owns this publishing configuration. Check deployment logs in the repository's Actions tab or `gh api repos/bechou0410/gmaphud/pages/builds/latest`.

The primary [installation source](https://gmaphud.caidat.app/) uses a Cloudflare Pages proxy to count full package-download starts by day, version and architecture. Existing GitHub Pages clients keep working through the fallback source. See [download statistics](docs/download-statistics.md) for the proxy source, aggregate queries, deployment and fallback behavior.

`docs/CydiaIcon*.png` are the repository icons Sileo fetches from the source root. The `Icon` field in [tweak/control](tweak/control) is the separate package icon; `docs/gmaphud-icon.svg/png` serve the website favicon and branding.

To publish an audited package, run `python3 build-repo.py packages/<rootless>.deb packages/<rootful>.deb` with Python 3 and `dpkg-deb` installed, review the resulting `docs/` changes, then commit and push. The index advertises the supplied version; previous package files remain available for existing downloads. Published filenames are immutable: bump the version before changing package bytes. Only reviewed release packages belong in this source. YTHUD is a separate experimental rootless package; append its .deb as the third argument when publishing it. A later GMapHUD-only invocation retains the published YTHUD record and verifies its artifact. Never put logs, keys, app dumps or other local files in `docs/`; the entire directory becomes public.

This is a flat HTTPS APT source (`deb https://gmaphud.caidat.app/ ./`) with package/index checksums. Release metadata is not PGP-signed; checksums alone do not authenticate the publisher. No global APT trust/security overrides are supplied. To roll back a source publication, revert its commit and push, retaining any already published package files. Confirm that the Pages build succeeded and public indexes match the intended package before announcing an update.

Rollback through a new higher package version if clients have already upgraded; reverting the source index alone does not downgrade installed packages.

## Stationary display test

Run on the phone in a shell with access to the installed tool while Google Maps is open in CarPlay:

```sh
/var/jb/usr/bin/gvm-test-speed 42 50 60
/var/jb/usr/bin/gvm-test-speed 48 50 60
/var/jb/usr/bin/gvm-test-speed 62 50 60
/var/jb/usr/bin/gvm-test-speed 42 60 60 speed_limit_80:200 no_passing_in:400
/var/jb/usr/bin/gvm-test-speed 42 60 60 lanes=1,1,1,5,4@127
/var/jb/usr/bin/gvm-test-speed 95 90 60 lanes=1:90,5:70
/var/jb/usr/bin/gvm-test-speed options limit
/var/jb/usr/bin/gvm-test-speed off
```

Arguments: current speed (0–400 km/h), limit (1–400 km/h), duration (1–300 seconds), and optionally two VietMap asset names with distances (0–10000 m each), as `SIGN:METERS`, for trial 0.1.14. Bare distance numbers remain accepted as camera signs; `SIGN:-` shows a sign in effect, without a distance. `lanes=CODES@METERS` adds up to seven test lanes in VietMap's lane codes (1 straight, 4 right, 5 straight or right, 16 U-turn, 64 left, and their sums), left to right; prefix a code with `x` for a lane not to use, and leave out `@METERS` for no distance. Add `:LIMIT` to every lane for its speed limit sign (`0` or `-1` for a sign without a number, `-2` or less for a grey one; code `0` for a lane without an arrow). Lanes show on New UI (beta). `options speed|limit` temporarily sets the New UI large circle without overwriting the saved choice. Only the Google CarPlay display model changes; GPS, navigation and real VietMap data remain unchanged. By default, TEST remains visible until `off` or expiry. Missing live values remain missing after testing.

## Diagnostics

After installing, close and reopen both Google Maps and VietMap Live. Reproduce the issue, then open **Settings → GMapHUD → Chẩn đoán / Xuất log**. Tap **Làm mới** (Refresh), then **Sao chép báo cáo** (Copy report) or **Xuất file…** (Export file) to share a `.txt` report. Review the visible report first; nothing is uploaded automatically.

The summary includes hardware model (no serial number), OS, hook/channel status, sample freshness and CarPlay rendering checkpoints. It retains up to 16 recent checkpoints per app plus the last checkpoint for each stage. The summary excludes coordinates, routes and accounts. Notification state may disappear when processes or the notification service restart; collect it while reproducing the issue. Add the jailbreak version and split-screen tweak name manually when requesting support.

Version 0.1.21 also reads installed Google Maps and VietMap Live version and build metadata independently of module checkpoints. Unsupported metadata access is reported as unavailable. Refresh lists up to three readable related `.ips`/`.crash` files from the last seven days (at most 2 MB each); exporting can include these original files beside the summary. Disable **Đính kèm crash liên quan** to export only the summary. Crash files can contain device/app identifiers or other personal information; inspect attachments before sharing. Inaccessible or missing crash logs are reported explicitly, not treated as proof that no crash occurred.


## Architecture and privacy

`provider/vietmap-source.x` observes the existing VietMap Flutter overlay channel and forwards its original handler/reply unchanged. Validated speed and limit, each with their own monotonic receive time, travel through local Darwin notification state. Road alerts are decoded from JSON-string items in `vml_main_channel/updateUpcommingAlerts` and `updateStickyAlerts`, matched against exact 3.4.3 asset digests, and converted by a VietMap adapter into up to two semantic road alerts. The tweak uses a [versioned common source output](docs/source-output-contract.md) for speed, limit and alerts on both Google Maps surfaces. Each frame belongs to one selected source; partial frames and old source selections are refused. Empty lists clear their source; original timestamps expire after five seconds. The package includes redesigned display artwork supplied for GMapHUD, separately from source image recognition; notifications remain numeric only. CarPlay hooks apply them to external map windows. A separate foreground-only overlay displays the same fresh data in the Google Maps iPhone window without intercepting touches.

The tweak creates no network listener, telemetry upload, publisher daemon or saved credentials. App-sandbox `tmp/googlemaps-vietmap-source.log` and `tmp/googlemaps-vietmap.log` record numeric speed/limit availability and hook status, not coordinates or routes. Local notification state is not cryptographically authenticated and can be affected by other privileged/injected software. Review device logs before sharing.

## License

Project-authored code is offered under [MIT](LICENSE). Current display artwork is supplied by the user; replacing images does not establish their provenance or grant redistribution rights. Artwork is not automatically covered by the code’s MIT license. Older published packages may contain original VietMap images. Third-party apps, maps, traffic/sign data, trademarks, SDKs and dependencies retain their owners' rights and terms. See [DISCLAIMER.md](DISCLAIMER.md) for lawful-use, safety, compatibility and warranty notices. Licensing does not certify legality, accuracy or roadworthiness.

For unedited Settings screenshots, append `--photo` to hide the badge for that bounded sample only. `gvm-test-speed position top-left left` changes Full Map/Dashboard placement temporarily without writing user preferences; restore the previous placement after capture.

## Automatic VietMap wake

After installation, respring once to load the SpringBoard component. In iOS Settings, enable Location Services and grant VietMap Live **When In Use** or **Always** location access, then enable **Settings → GMapHUD → Tự đánh thức VietMap Live**. The switch defaults to off and stays disabled until these conditions are confirmed. It refreshes while the page is visible. Revoking permission or disabling Location Services turns the feature off; restoring permission does not automatically turn it on again.

While Google Maps is visible on CarPlay or iPhone, GMapHUD can launch VietMap in the background and keep it active without bringing it to the foreground. Enable alerts in VietMap first; the tweak cannot sign in, activate a subscription or guarantee fresh data. Relaunch attempts are bounded to avoid a restart loop. Leaving Google Maps on both screens releases the added background session after the heartbeat expires; VietMap retains its real location permission. Private system APIs can vary by iOS version; if unavailable, automatic wake remains disabled. Runtime wake was tested on iPhone 11/iOS 18.6.2; the new switch gating has host/build validation, not complete on-device permission-transition validation on every supported OS. Rootful/iOS 14 behavior remains unverified. Automatic wake applies to the selected VietMap Live, Waze or GOFA source.

Background state is recorded locally in `/var/mobile/Library/Logs/gmaphud-background.log` (bounded, no coordinates). Google Maps can request a fresh retransmission from the running source; cached values retain their original timestamps and expire normally.

## Overspeed warning

Settings → GMapHUD → Cảnh báo vượt tốc offers Off, Map or Entire screen. Fresh speed above the current limit triggers a pulsing red inward glow. Map scope covers only the Google Maps viewport; Entire screen includes the sidebar and Dashboard tiles. This warning does not apply on iPhone.

Pulse frequency follows excess speed: below 5 km/h — 0.75 Hz; 5 to below 10 — 1.25 Hz; 10 or more — 2 Hz. Map scope follows the visible viewport after sidebar and ancestor clipping are excluded.

Glow intensity is scoped separately: map warning is stronger, whole-screen warning is softer; excess-speed pulse rates are unchanged.


## Bubble settings

In Settings → GMapHUD, pick Classic or New UI (beta) under Giao diện; the change applies to every screen without reopening Google Maps. Then choose Full Map, Dashboard or iPhone. Each page includes its own switch, position, Auto/Horizontal/Vertical layout, size and drag-to-reorder controls. Both previews update with the order. iPhone also has X/Y positioning. Reset restores only its associated setting.

In **Background**, enable automatic wake of the selected source or optional source exit 20 seconds after CarPlay disconnect. While Google Maps is shown, a selected source that is not running is launched in the background, at most every 3 seconds; after 5 failed attempts (an app that keeps crashing or is not installed) GMapHUD uses the next installed source with location permission, in the order VietMap Live, GOFA, Waze, until the next Google Maps session, without changing the choice saved in Settings; when none is left, waking stops until then, while a source you open yourself is still kept running. GMapHUD closes only a source it launched itself that has not been on the iPhone or CarPlay screen since: when another source is selected, and 10 seconds after Google Maps is closed. Existing location permissions are preserved.

## Other packages

**[YTHUD](ythud/README.md)** — Experimental rootless package for YouTube video in the Dashboard music tile. Uses method-ABI checks without an app-version lock; tested with YouTube 21.41.5 and an existing CarPlay app bridge. Livestream is unsupported; an intermittent black picture when returning to YouTube is unresolved. [Depiction](https://bechou0410.github.io/gmaphud/ythud/).

**[CarPlay Scale](carplay-scale/README.md)** — Experimental rootless package that draws the CarPlay interface smaller so more content fits, without changing the video sent to the car. Settings offers 90%–70% and an Apply button. Tested on iOS 18.6.2 with a real head unit and CarPlay Simulator. [Depiction](https://bechou0410.github.io/gmaphud/carplay-scale/).
