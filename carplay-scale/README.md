# CarPlay Scale

Experimental rootless tweak that draws the CarPlay interface smaller so more content fits: a wider map, a slimmer dock and widgets. The video sent to the car keeps its resolution; only the iPhone lays out more points. Author: chou · AI-assisted with Claude. Project-authored code is covered by the repository [MIT license](../LICENSE).

## Install and use

Add **https://gmaphud.caidat.app/** to Sileo or Zebra, refresh and search for **CarPlay Scale**. The [GitHub Pages source](https://bechou0410.github.io/gmaphud/) remains a fallback. Read the [bilingual depiction](https://bechou0410.github.io/gmaphud/carplay-scale/) before installing.

After installation CarPlay restarts and uses the default 80% size. In Settings → **CarPlay Scale**:

- **Thu nhỏ giao diện** (shrink interface) switch.
- **Cỡ giao diện** (interface size): 90%, 85%, 80%, 75% or 70%. An 800x480 head unit has 400x240 points at its native scale and 500x300 points at 80%.
- **Áp dụng** (Apply), at the bottom of both pages. Changing the switch or the size only saves it; Apply restarts the CarPlay interface with the new choice in about a second. Without Apply, the choice is used from the next CarPlay connection.

Tested: iPhone 11 / iOS 18.6.2 rootless with ElleKit and CarPlay Simulator at 800x480 and 748x456, including reconnects and touch input. Not yet tested on a real head unit. Only rootless is supplied (arm64 and arm64e code).

## How it works

CarKit picks the CarPlay point scale from the head unit's pixel size (2x up to about 1100x660, 3x above). CarPlay.app builds the display configuration that CarPlay and the apps on it lay out against. The tweak is injected only into CarPlay.app and hooks `-[FBSDisplayConfiguration _initWithImmutableDisplay:originalDisplay:assertIfInvalid:]`: for the `VideoStream.Main` screen it returns a copy whose mode keeps the pixel size and divides the point scale by the chosen size. The width is a whole number of points; [scale-math.m](common/scale-math.m) keeps every pixel row and column after FrontBoard's rounding.

Settings are stored in the CFPreferences domain `com.chou.carplayscale` (`enabled`, `percent`); Apply posts `com.chou.carplayscale/changed`, and CarPlay.app quits so the system relaunches it with the new size. A crash-loop guard turns scaling off after two launches in a row that did not run for 10 seconds; the next save or Apply re-arms it. The package scripts restart CarPlay.app on install and removal.

## Limitations

Banners, Siri and alerts drawn by SpringBoard keep the original size; secondary screens (instrument clusters) are unchanged. Several changes in a row can take up to about 5 seconds, because iOS throttles relaunching CarPlay.app.

## Build

Use macOS, Xcode command-line tools and Theos.

```sh
sh carplay-scale/test.sh
sh carplay-scale/build-package.sh
```

Run them from the repository root; the build runs the host tests first. The .deb appears in `carplay-scale/packages/`. To publish it alongside the current GMapHUD pair (and the published YTHUD, which is retained), run `python3 build-repo.py docs/pool/com.chou.googlemaps.vietmap_0.2.5_iphoneos-arm64.deb docs/pool/com.chou.googlemaps.vietmap_0.2.5_iphoneos-arm.deb carplay-scale/packages/com.chou.carplayscale_0.1.7_iphoneos-arm64.deb`, using the currently published GMapHUD version for later releases.

## Tiếng Việt

Thêm nguồn trên vào Sileo/Zebra, làm mới rồi tìm **CarPlay Scale**. Gói vẽ giao diện CarPlay nhỏ lại để thấy được nhiều nội dung hơn; hình gửi sang xe giữ nguyên độ phân giải. Cài xong, CarPlay tự khởi động lại với cỡ mặc định 80%. Vào Cài đặt → CarPlay Scale: gạt **Thu nhỏ giao diện** hoặc chọn **Cỡ giao diện** (90%–70%), rồi bấm **Áp dụng**; không bấm thì lựa chọn mới được dùng từ lần kết nối CarPlay sau. Chỉ hỗ trợ rootless; đã kiểm trên iOS 18.6.2 với CarPlay Simulator, chưa kiểm trên đầu xe thật. Banner, Siri và cảnh báo của hệ thống vẫn giữ cỡ gốc. Xem [trang mô tả](https://bechou0410.github.io/gmaphud/carplay-scale/) trước khi cài.
