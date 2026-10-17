# YTHUD

Experimental rootless tweak that shows YouTube video in the CarPlay Dashboard Now Playing music tile. Author: chou · AI-assisted with Codex. Project-authored code is covered by the repository [MIT license](../LICENSE).

## Install and use

Add **https://gmaphud.caidat.app/** to Sileo or Zebra, refresh and search for **YTHUD**. The [GitHub Pages source](https://bechou0410.github.io/gmaphud/) remains a fallback. Read the [bilingual depiction](https://bechou0410.github.io/gmaphud/ythud/) before installing.

Tested core: iPhone 11 / iOS 18.6.2 rootless with ElleKit, YouTube **21.41.5**, CarSurf and CarPlay Simulator. The YouTube hook checks that exact version and method ABI; other versions keep their native backend. An existing app bridge is required to open YouTube on CarPlay; this package supplies no launcher or bridge. Only rootless is supplied (arm64 and arm64e code).

After installation, reopen YouTube and reconnect CarPlay, or respring. Play a normal video in YouTube on CarPlay and open Dashboard. The native Next, Pause/Play and autoplay controls continue to apply. Returning to YouTube restores the current item and playback position; single-tap the mini player to expand it. Uninstall through the package manager and reopen the affected apps. Package scripts do not stop running apps.

The package conflicts with and replaces the preceding local `com.chou.youtube-dashboard` package; review the package manager’s removal transaction. It also removes the four known unmanaged source/host trial files to prevent duplicate hooks.

## Limitations

Livestream does not export to Dashboard. One earlier clip returned black after Next/Pause and remained black on resume; subsequent successful return tests do not establish a fix. Ads, screen locking, accessory reconnection and long-term stability are not fully verified. Version 0.1.0 remains experimental. No audio was recorded in the captured verification movies.

## Build

Use macOS, Xcode command-line tools, Theos and an iPhoneOS 16.5 SDK obtained separately. No SDK or third-party app binary is bundled.

```sh
sh ythud/build-package.sh
```

Run that from the repository root. The .deb appears in `ythud/packages/`. To publish it alongside the current GMapHUD pair, run `python3 build-repo.py docs/pool/com.chou.googlemaps.vietmap_0.2.5_iphoneos-arm64.deb docs/pool/com.chou.googlemaps.vietmap_0.2.5_iphoneos-arm.deb ythud/packages/com.chou.ythud_0.1.0_iphoneos-arm64.deb` (use the currently published GMapHUD version for later releases). The disposable build directory is removed when the script exits. Both injection targets build with `YTAV_RELEASE=1`; there is no 30-minute trial deadline, command-file setup, inspector/source observer, diagnostic logging or test border.

The dedicated output uses the AVPlayer/item selected by YouTube, without a second player/stream, PiP, scene hold, window crop or Maps hook. Source ownership, version/ABI guards and invalid/dead context checks remain. The private Darwin notification namespace stays `com.duodash.youtube.dashboard` to preserve the tested protocol; it is not a user-visible product name.

## Tiếng Việt

Thêm nguồn trên vào Sileo/Zebra, làm mới rồi tìm **YTHUD**. Gói chỉ hỗ trợ rootless và khóa YouTube 21.41.5; cần bridge CarPlay đang có. Mở lại YouTube/kết nối lại CarPlay sau khi cài. Livestream chưa hỗ trợ; đã ghi nhận lỗi quay về app bị đen hình ở một clip và chưa khắc phục. Xem [trang mô tả](https://bechou0410.github.io/gmaphud/ythud/) để biết phạm vi trước khi cài.
