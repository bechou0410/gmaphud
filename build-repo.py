#!/usr/bin/env python3
"""Publish audited GMapHUD packages and optional companion packages into the static source."""
import bz2
from datetime import datetime, timezone
from email.utils import format_datetime
import gzip
import hashlib
import html
import json
import lzma
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
URL = "https://bechou0410.github.io/gmaphud/"
SOURCE_URL = "https://gmaphud.caidat.app/"
SILEO_DEPICTION_URL = URL + "sileo-depiction.json"
# Companion packages published next to GMapHUD: package identifier -> (display name, repository directory).
# Each is rootless only, appears at most once and keeps this order in the index.
COMPANIONS = {
    "com.chou.ythud": ("YTHUD", "ythud"),
    "com.chou.carplayscale": ("CarPlay Scale", "carplay-scale"),
}


def companion_links(package_id):
    directory = COMPANIONS[package_id][1]
    return {
        "Homepage": f"https://github.com/bechou0410/gmaphud/tree/main/{directory}",
        "Bugs": "https://github.com/bechou0410/gmaphud/issues",
        "Depiction": URL + directory + "/",
        "SileoDepiction": URL + directory + "/sileo-depiction.json",
    }


HASHES = (("MD5sum", "md5"), ("SHA1", "sha1"), ("SHA256", "sha256"), ("SHA512", "sha512"))
INDEX_FIELDS = {"Filename", "Size", *(field for field, _ in HASHES)}
SCREENSHOTS = (
    URL + "screenshots/full-map-top-left.png",
    URL + "screenshots/full-map-top-right.png",
    URL + "screenshots/full-map-bottom-left.png",
    URL + "screenshots/full-map-bottom-right.png",
    URL + "screenshots/dashboard-left.png",
    URL + "screenshots/dashboard-right.png",
)


def build_sileo_depiction():
    screenshots = {
        "vi": [
            "Bản đồ đầy đủ: bong bóng ở góc trên trái.",
            "Bản đồ đầy đủ: bong bóng ở góc trên phải.",
            "Bản đồ đầy đủ: bong bóng ở góc dưới trái.",
            "Bản đồ đầy đủ: bong bóng ở góc dưới phải.",
            "Dashboard: bong bóng ở bên trái.",
            "Dashboard: bong bóng ở bên phải.",
        ],
        "en": [
            "Full map: bubble in the top-left corner.",
            "Full map: bubble in the top-right corner.",
            "Full map: bubble in the bottom-left corner.",
            "Full map: bubble in the bottom-right corner.",
            "Dashboard: bubble on the left.",
            "Dashboard: bubble on the right.",
        ],
    }
    copy = {
        "vi": {
            "tab": "Tiếng Việt",
            "title": "GMapHUD trên CarPlay và iPhone",
            "intro": (
                "Hiển thị tốc độ hiện tại, giới hạn và cảnh báo đường nhận diện được từ VietMap Live, Waze hoặc GOFA trong Google Maps trên CarPlay và iPhone. "
                "Google Maps tiếp tục đảm nhiệm việc dẫn đường."
            ),
            "screenshots": "Vị trí bong bóng · ảnh xem trước trong Cài đặt",
            "compatibility": "Thiết lập đã kiểm thử",
            "compatibility_text": (
                "iPhone 11 · iOS 18.6.2 rootless · Google Maps 26.40.3 "
                "· VietMap Live 3.4.3; đã xác nhận dữ liệu 0/50."
            ),
            "safety": "Phạm vi và lưu ý",
            "safety_text": (
                "Ảnh dùng tuyến giả lập; không chứng minh độ chính xác ngoài đường thực tế. "
                "Dữ liệu có thể sai, trễ hoặc thiếu. Chỉ dùng để nghiên cứu/kiểm thử khi xe đã đỗ an toàn; "
                "tuân thủ biển báo thực tế. Không phải thiết bị hỗ trợ lái xe được chứng nhận.\n\n"
                "Hiển thị tốc độ, giới hạn và tối đa hai cảnh báo đường đã nhận diện; không có cảnh báo âm thanh, giả lập GPS "
                "hay vượt thuê bao/DRM. Mã do dự án viết theo giấy phép MIT; quyền với ứng dụng, dữ liệu và hình ảnh bên thứ ba vẫn thuộc chủ sở hữu. Dự án độc lập, không được "
                "VietMap, Google hay Apple bảo trợ."
            ),
            "links": "Liên kết",
            "links_text": (
                f"[Trang chủ]({URL}) · [GitHub](https://github.com/bechou0410/gmaphud) · "
                f"[Thông báo trách nhiệm]({URL}notices.html#vi)"
            ),
        },
        "en": {
            "tab": "English",
            "title": "GMapHUD on CarPlay and iPhone",
            "intro": (
                "Displays current speed, limits, and recognized VietMap road alerts in Google Maps on CarPlay and iPhone. "
                "Google Maps continues to handle navigation."
            ),
            "screenshots": "Bubble placement · Settings previews",
            "compatibility": "Tested setup",
            "compatibility_text": (
                "iPhone 11 · iOS 18.6.2 rootless · Google Maps 26.40.3 "
                "· VietMap Live 3.4.3; verified 0/50 data."
            ),
            "safety": "Scope and safety",
            "safety_text": (
                "Screenshots use a simulated route; they do not establish real-road accuracy. "
                "Readings may be wrong, delayed, or missing. For research and stationary testing only; "
                "follow actual signs. This is not a certified driving aid.\n\n"
                "Speed, limits, and up to two recognized road alerts; no audible alerts, GPS simulation, or subscription/DRM "
                "bypass. Project-authored code is MIT-licensed; third-party apps, data and artwork retain their owners’ rights. Independent project, not endorsed by VietMap, Google, or Apple."
            ),
            "links": "Links",
            "links_text": (
                f"[Project website]({URL}) · [GitHub](https://github.com/bechou0410/gmaphud) · "
                f"[Disclaimer]({URL}notices.html#en)"
            ),
        },
    }
    changelog = (
        ("0.2.6", "Nguồn cảnh báo chạy nền ổn định hơn: khi Google Maps hiện, GMapHUD mở lại nguồn đã chọn mỗi 3 giây nếu nguồn chưa gửi dữ liệu, kể cả sau khi app nguồn bị đóng hoặc lỗi; sau 5 lần không được thì tạm dùng nguồn khác đã cài và có quyền vị trí, không đổi lựa chọn trong Cài đặt. GMapHUD chỉ đóng nguồn do nó tự mở và chưa từng hiện trên iPhone hay CarPlay, khi đổi nguồn hoặc 10 giây sau khi Google Maps đóng. Google Maps cập nhật ngay khi nguồn có dữ liệu mới. VietMap Live: có tốc độ hiện tại khi chỉ dùng Google Maps trên iPhone hoặc trên CarPlay không có kênh xe của VietMap. Waze: không còn chỉ nhận bản 5.25.0. Làn đường hiện ngay khi VietMap đếm ngược tới giao lộ, kèm khoảng cách; thêm biển làn phía trước của GOFA và biển tốc độ từng làn của VietMap (ví dụ trên cao tốc). Thêm mục Vòng lớn: vòng lớn là biển giới hạn, vòng nhỏ là tốc độ. Mở lại VietMap Live, Waze hoặc GOFA sau khi cập nhật.",
         "Keeps the alert source running in the background more reliably: while Google Maps is shown, GMapHUD relaunches the selected source every 3 s until it sends data, also after the source app was closed or crashed; after 5 failed attempts it uses another installed source with location permission for the session, without changing Settings. GMapHUD closes only sources it launched that were never on the iPhone or CarPlay screen, on a source switch or 10 s after Google Maps closes. Google Maps updates as soon as the source has new data. VietMap Live: current speed with Google Maps on the iPhone alone or on CarPlay units without VietMap's car channel. Waze: no longer limited to 5.25.0. Lanes show as soon as VietMap counts down to a junction, with the distance; adds GOFA's lane sign ahead and VietMap's per-lane speed limits (on expressways, for example). Adds Vòng lớn: the large circle is the limit sign, the small one the speed. Reopen VietMap Live, Waze or GOFA after updating."),
        ("0.2.5", "Sửa thanh trượt Trái/phải và Lên/xuống của bong bóng trên iPhone: không kéo được ở 0.2.4, và hiện 100% khi mở lại Cài đặt nếu bong bóng lệch sang trái hoặc lên trên.",
         "Fixes the iPhone bubble's left/right and up/down sliders: they could not be dragged in 0.2.4, and showed 100% on reopening Settings for a left or up offset."),
        ("0.2.4", "Thêm mục Giao diện: Classic (mặc định) hoặc New UI (beta) với đồng hồ tốc độ tròn, biển giới hạn ghim trên đồng hồ và biển làn đường theo VietMap Live; khi dẫn đường trên CarPlay, biển hiệu lực và làn nằm dưới ô chỉ dẫn. Vẽ lại bộ biển báo theo QCVN 41:2024, kích cỡ bong bóng tới 250%. Sửa biển hiệu lực hiện 0 m và nhấp nháy.",
         "Adds an Interface choice: Classic (default) or New UI (beta), with a round speed dial, the limit pinned on it and VietMap Live lane signs; while navigating on CarPlay, signs in effect and lanes sit under the maneuver card. Redraws road signs to QCVN 41:2024 and allows bubble sizes up to 250%. Fixes signs in effect showing 0 m and blinking."),
        ("0.2.3", "Đánh thức và duy trì nguồn cảnh báo khi chỉ dùng Google Maps trên iPhone, kể cả sau khi vừa ngắt CarPlay. Banner hay Trung tâm điều khiển không còn làm ngắt nguồn.",
         "Wakes and keeps the warning source when using Google Maps on iPhone only, including right after CarPlay disconnects. Banners or Control Center no longer end the source session."),
        ("0.2.2", "Giữ giới hạn tốc độ của Waze và GOFA ổn định khi điện thoại đứng yên; GOFA không còn mất giới hạn khi chạy nền. Cải thiện độ ổn định định vị nền.",
         "Keeps Waze and GOFA speed limits steady while the phone is stationary; GOFA no longer loses the limit in the background. Improves background location stability."),
        ("0.2.1", "Thêm nguồn cảnh báo Waze và GOFA, bổ sung bộ icon cảnh báo. Cải thiện chạy nền và độ ổn định tốc độ, giới hạn và cảnh báo đường.",
         "Adds Waze and GOFA warning sources and new warning icons. Improves background operation and stability of speed, limits and road alerts."),
        ("0.2", "Làm gọn Cài đặt, thêm kéo thả và xem trước bố cục. Bổ sung tùy chọn thoát nguồn khi ngắt CarPlay; sửa cảnh báo vượt tốc chặn thao tác. Hiện hỗ trợ VietMap Live.",
         "Simplifies Settings with drag ordering and layout previews. Adds optional source exit after CarPlay disconnect and fixes overspeed warnings blocking controls. VietMap Live is currently supported."),
        ("0.1.22", "Cập nhật bộ icon biển báo; đồng bộ font số trên biển giới hạn tốc độ chính.",
         "Updates road-sign icons and aligns the main speed-limit digits with the new artwork."),
        ("0.1.21", "Tùy chỉnh bố cục ngang/dọc và kéo đổi thứ tự các phần trong bong bóng. Làm mới Cài đặt, thêm công tắc từng màn hình và nút đặt lại. Cập nhật bộ icon biển báo, giữ kích cỡ Dashboard ổn định khi đổi bố cục hoặc thêm/bớt cảnh báo. Báo cáo hỗ trợ có thêm phiên bản ứng dụng và tùy chọn đính kèm crash.",
         "Customize horizontal/vertical layouts and drag to reorder bubble sections. Refreshes Settings with per-screen switches and reset controls. Updates road-sign icons and keeps Dashboard content sizes stable when changing layouts or adding/removing alerts. Support reports now include app versions and optional crash attachments."),
        ("0.1.20", "Cải thiện tính ổn định", "Improved stability"),
        ("0.1.19", "Tối ưu cập nhật bong bóng và giảm dung lượng gói cài. Tự đánh thức VietMap Live hỗ trợ cả Google Maps trên CarPlay và iPhone, với quyền định vị Khi dùng ứng dụng hoặc Luôn luôn. Cải thiện tự nhận lại dữ liệu khi VietMap chưa chạy; làm gọn mô tả trong Cài đặt.",
         "Optimizes bubble updates and reduces package size. Automatic VietMap Live wake now supports Google Maps on both CarPlay and iPhone with When In Use or Always location access. Improves data recovery when VietMap is not running and simplifies Settings descriptions."),
        ("0.1.18", "Thêm bong bóng trong Google Maps trên iPhone, chọn bốn góc và tinh chỉnh vị trí tự do; hỗ trợ bố cục Tự động, Ngang hoặc Dọc. Chỉnh kích cỡ riêng cho bản đồ CarPlay đầy đủ, Dashboard và iPhone. Làm gọn giao diện Cài đặt; sửa lỗi bong bóng bị bóp hẹp khi dẫn đường và giữ kích thước đồng nhất giữa các góc.",
         "Adds a bubble inside Google Maps on iPhone with four corners, flexible positioning, and Auto, Horizontal or Vertical layouts. Adjust size separately for CarPlay Full Map, Dashboard and iPhone. Refreshes Settings controls and fixes squeezed navigation bubbles while keeping sizes consistent across corners."),
        ("0.1.17", "Thêm tùy chọn tự đánh thức VietMap Live khi mở Google Maps trên CarPlay. Công tắc chỉ khả dụng khi đã cấp định vị Luôn luôn; tự tắt nếu không còn đủ quyền. Cải thiện kết nối dữ liệu và chẩn đoán.",
         "Adds optional background wake for VietMap Live while Google Maps is shown on CarPlay. Requires Always location permission; the switch turns off when requirements are no longer met. Improves data delivery and diagnostics."),
        ("0.1.16", "Bổ sung gói rootful cùng nguồn Sileo với rootless. Bản rootful cần kiểm thử thực tế trên iOS 14; giữ tính năng chẩn đoán để gửi hỗ trợ.",
         "Adds a rootful package alongside rootless in the same Sileo source. Rootful still needs iOS 14 device testing; support diagnostics remain available."),
        ("0.1.15", "Thêm mục Chẩn đoán trong Cài đặt: xem, sao chép hoặc xuất báo cáo để được hỗ trợ khi bong bóng thiếu thông tin. Không thu thập vị trí hay tự gửi báo cáo.",
         "Adds Diagnostics in Settings: view, copy or export a report to help troubleshoot missing bubble data. No location collection or automatic uploads."),
        ("0.1.14", "Bổ sung cảnh báo đường sắp tới như giới hạn tốc độ và camera; thêm tùy chỉnh vị trí bong bóng cùng ảnh xem trước trong Cài đặt.",
         "Adds upcoming road alerts such as speed limits and cameras, plus bubble placement controls and previews in Settings."),
        ("0.1.13", "Bỏ khóa phiên bản Google Maps và VietMap Live; giữ kiểm tra cấu trúc hàm và dữ liệu. Đã nhận dữ liệu 0/50 trên Google Maps 26.40.3 và VietMap Live 3.4.3.",
         "Removes Google Maps and VietMap Live version restrictions while retaining method and data checks. Verified 0/50 data with Google Maps 26.40.3 and VietMap Live 3.4.3."),
        ("0.1.12", "Cập nhật ghi nhận tác giả dự án là chou và nêu rõ Codex hỗ trợ phát triển bằng AI.",
         "Credits chou as project author and discloses Codex AI development assistance."),
        ("0.1.11", "Bản trước trong nguồn Sileo; không có ghi chú phát hành riêng.",
         "Previous package in the Sileo source; no separate release notes published."),
        ("0.1.10", "Hoàn thiện nhận diện dự án trong giấy phép MIT và tài liệu đóng kèm; thống nhất đường dẫn GitHub/Sileo. Tích hợp tốc độ không đổi so với 0.1.8.",
         "Completed project branding in the MIT notice and bundled documents, and consolidated the GitHub/Sileo publication route. Speed integration unchanged from 0.1.8."),
        ("0.1.9", "Cập nhật tên dự án, thông báo đóng gói và liên kết xuất bản. Tích hợp tốc độ không đổi so với 0.1.8.",
         "Updated project/package branding, bundled notices, and publication links. Speed integration unchanged from 0.1.8."),
        ("0.1.8", "Bản thử nghiệm đầu tiên: hiển thị tốc độ và giới hạn từ VietMap Live trên Google Maps CarPlay, gồm bảng trên bản đồ và thẻ Dashboard; kèm công cụ kiểm thử hiển thị khi xe đã đỗ.",
         "First experimental release: displays VietMap Live speed and limits in Google Maps CarPlay, with a full-map pill and Dashboard card; includes a stationary display-test tool."),
    )
    tabs = []
    for language in ("vi", "en"):
        text = copy[language]
        tabs.append({
            "class": "DepictionStackView",
            "tabname": text["tab"],
            "views": [
                {"class": "DepictionHeaderView", "title": text["title"]},
                {"class": "DepictionMarkdownView", "markdown": text["intro"]},
                {"class": "DepictionSubheaderView", "title": text["screenshots"]},
                {
                    "class": "DepictionScreenshotsView",
                    "itemSize": "{320, 192}",
                    "itemCornerRadius": 10,
                    "screenshots": [
                        {"url": url, "accessibilityText": description}
                        for url, description in zip(SCREENSHOTS, screenshots[language])
                    ],
                },
                {"class": "DepictionSubheaderView", "title": text["compatibility"]},
                {"class": "DepictionMarkdownView", "markdown": text["compatibility_text"]},
                {"class": "DepictionSubheaderView", "title": text["safety"]},
                {"class": "DepictionMarkdownView", "markdown": text["safety_text"]},
                {"class": "DepictionSubheaderView", "title": text["links"]},
                {"class": "DepictionMarkdownView", "markdown": text["links_text"]},
            ],
        })
    change_views = [{"class": "DepictionHeaderView", "title": "Nhật ký thay đổi / Change log"}]
    for version, vi, en in changelog:
        change_views.extend([
            {"class": "DepictionSubheaderView", "title": version},
            {"class": "DepictionMarkdownView", "markdown": f"**Tiếng Việt:** {vi}\n\n**English:** {en}"},
        ])
    tabs.append({
        "class": "DepictionStackView",
        "tabname": "Nhật ký / Changes",
        "views": change_views,
    })
    return {
        "minVersion": "0.4",
        "class": "DepictionTabView",
        "tintColor": "#9BE8B8",
        "tabs": tabs,
    }


def control_fields(control):
    fields = {}
    key = None
    for line in control.splitlines():
        if line.startswith((" ", "\t")) and key:
            fields[key] += "\n" + line
            continue
        match = re.fullmatch(r"([A-Za-z][A-Za-z0-9-]*): (.*)", line)
        if not match or match[1] in fields:
            raise SystemExit("Invalid or duplicate package metadata field.")
        key = match[1]
        fields[key] = match[2]
    return fields


def read_package(package, package_id, architectures):
    data = package.read_bytes()
    control = subprocess.check_output(["dpkg-deb", "--field", str(package)], text=True).strip()
    fields = control_fields(control)
    arch = fields.get("Architecture")
    if fields.get("Package") != package_id or arch not in architectures:
        raise SystemExit(f"Unexpected package identity or architecture for {package_id}.")
    version = fields.get("Version", "")
    if not re.fullmatch(r"[A-Za-z0-9.+:~\-]+", version):
        raise SystemExit("Invalid package version.")
    if INDEX_FIELDS & fields.keys():
        raise SystemExit("Package control must not contain repository index fields.")
    if package_id in COMPANIONS and any(fields.get(key) != value for key, value in companion_links(package_id).items()):
        raise SystemExit(f"{COMPANIONS[package_id][0]} must declare its dedicated publication links.")
    name = f"{package_id}_{version}_{arch}.deb"
    return arch, (version, name, data, control)


def published_companions(site):
    """Returns the validated index stanzas of companion packages already published, by package identifier."""
    index = site / "Packages"
    retained = {}
    if not index.exists():
        return retained
    for stanza in index.read_text(encoding="utf-8").strip().split("\n\n"):
        if not stanza:
            continue
        fields = control_fields(stanza)
        package_id = fields.get("Package")
        if package_id == "com.chou.googlemaps.vietmap":
            continue
        if package_id not in COMPANIONS or package_id in retained:
            raise SystemExit("Expected at most one published package of each companion alongside GMapHUD.")
        name = COMPANIONS[package_id][0]
        version = fields.get("Version", "")
        if not re.fullmatch(r"[A-Za-z0-9.+:~\-]+", version):
            raise SystemExit(f"Invalid published {name} version.")
        filename = f"pool/{package_id}_{version}_iphoneos-arm64.deb"
        if fields.get("Filename") != filename:
            raise SystemExit(f"Published {name} must reference its canonical pool filename.")
        package = site / filename
        if package.is_symlink() or not package.is_file():
            raise SystemExit(f"Published {name} artifact is missing or is not a regular file.")
        _, record = read_package(package, package_id, ("iphoneos-arm64",))
        data = record[2]
        if fields.get("Size") != str(len(data)) or any(
            fields.get(field) != hashlib.new(algorithm, data).hexdigest() for field, algorithm in HASHES
        ):
            raise SystemExit(f"Published {name} artifact does not match its size or checksums.")
        if {key: value for key, value in fields.items() if key not in INDEX_FIELDS} != control_fields(record[3]):
            raise SystemExit(f"Published {name} metadata does not match its package control.")
        retained[package_id] = stanza + "\n"
    return retained


def package_stanza(record, gmaphud=False):
    _, name, data, control = record
    stanza = control + "\n" + f"Filename: pool/{name}\nSize: {len(data)}\n"
    for field, algorithm in HASHES:
        stanza += f"{field}: {hashlib.new(algorithm, data).hexdigest()}\n"
    if gmaphud:
        stanza += f"Depiction: {URL}\nSileoDepiction: {SILEO_DEPICTION_URL}\n"
        stanza += "Homepage: https://github.com/bechou0410/gmaphud\nBugs: https://github.com/bechou0410/gmaphud/issues\n"
    return stanza


def main():
    if len(sys.argv) < 3:
        raise SystemExit("Usage: python3 build-repo.py rootless.deb rootful.deb [companion.deb ...]")
    site = ROOT / "docs"
    pool = site / "pool"
    records = {}
    for argument in sys.argv[1:3]:
        arch, record = read_package(Path(argument).resolve(strict=True), "com.chou.googlemaps.vietmap", ("iphoneos-arm", "iphoneos-arm64"))
        if arch in records:
            raise SystemExit("Expected one rootful and one rootless GMapHUD package.")
        records[arch] = record
    if len({record[0] for record in records.values()}) != 1:
        raise SystemExit("Both packages must have the same version.")
    companion_stanzas = published_companions(site)
    companions = {}
    for argument in sys.argv[3:]:
        package = Path(argument).resolve(strict=True)
        package_id = subprocess.check_output(["dpkg-deb", "--field", str(package), "Package"], text=True).strip()
        if package_id not in COMPANIONS or package_id in companions:
            raise SystemExit("Expected each companion package at most once.")
        _, companions[package_id] = read_package(package, package_id, ("iphoneos-arm64",))
        companion_stanzas[package_id] = package_stanza(companions[package_id])
    incoming = list(records.values()) + list(companions.values())
    for _, name, data, _ in incoming:
        target = pool / name
        if target.is_symlink() or (target.exists() and target.read_bytes() != data):
            raise SystemExit("Published package versions are immutable; bump the version first.")
    pool.mkdir(parents=True, exist_ok=True)
    for _, name, data, _ in incoming:
        (pool / name).write_bytes(data)
    stanzas = [package_stanza(record, gmaphud=True) for _, record in sorted(records.items())]
    stanzas += [companion_stanzas[package_id] for package_id in COMPANIONS if package_id in companion_stanzas]
    stanza = "\n".join(stanzas)
    version, name, data, _ = records["iphoneos-arm64"]
    indexes = {"Packages": stanza.encode()}
    indexes["Packages.gz"] = gzip.compress(indexes["Packages"], mtime=0)
    indexes["Packages.bz2"] = bz2.compress(indexes["Packages"])
    indexes["Packages.xz"] = lzma.compress(indexes["Packages"])
    for filename, content in indexes.items():
        (site / filename).write_bytes(content)
    (site / "sileo-depiction.json").write_text(
        json.dumps(build_sileo_depiction(), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    release = (
        "Origin: GMapHUD\nLabel: GMapHUD\nSuite: stable\nCodename: gmaphud\n"
        "Version: 1\nArchitectures: iphoneos-arm iphoneos-arm64\nComponents: main\n"
        "Description: Experimental VietMap speed integration for Google Maps CarPlay\n"
        f"Date: {format_datetime(datetime.now(timezone.utc), usegmt=True)}\n"
    )
    for field, algorithm in (("MD5Sum", "md5"), ("SHA256", "sha256"), ("SHA512", "sha512")):
        release += field + ":\n"
        for filename, content in indexes.items():
            release += f" {hashlib.new(algorithm, content).hexdigest()} {len(content)} {filename}\n"
    (site / "Release").write_text(release)
    template = (ROOT / "repo-template.html").read_text(encoding="utf-8")
    locales = json.loads((ROOT / "repo-locales.json").read_text(encoding="utf-8"))
    for language, filename in (("vi", "index.html"), ("en", "en.html")):
        values = {
            **locales[language],
            "LANG": language,
            "VERSION": version,
            "REPO_URL": SOURCE_URL,
            "FALLBACK_URL": URL,
            "PACKAGE_PATH": SOURCE_URL + "pool/" + name,
            "ROOTFUL_PACKAGE_PATH": SOURCE_URL + "pool/" + records["iphoneos-arm"][1],
            "VI_CURRENT": "page" if language == "vi" else "false",
            "EN_CURRENT": "page" if language == "en" else "false",
        }
        page = re.sub(r"\{\{([A-Z_]+)\}\}", lambda match: html.escape(values[match[1]], quote=True), template)
        (site / filename).write_text(page, encoding="utf-8")
    notices = "<!doctype html><html lang='vi'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>GMapHUD · Thông báo / Notices</title><style>body{max-width:800px;margin:40px auto;padding:0 20px;font:16px/1.6 system-ui}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:inherit}</style><a href='./'>GMapHUD</a><nav aria-label='Ngôn ngữ / Language'><a href='#vi' lang='vi'>Tiếng Việt</a> · <a href='#en' lang='en'>English</a> · <a href='#license' lang='en'>MIT</a></nav>"
    for section, language, filename in (("vi", "vi", "DISCLAIMER.vi.md"), ("en", "en", "DISCLAIMER.md"), ("license", "en", "LICENSE")):
        notices += f"<section id='{section}' lang='{language}'><h1>{html.escape(filename)}</h1><pre>{html.escape((ROOT / filename).read_text(encoding='utf-8'))}</pre></section>"
    (site / "notices.html").write_text(notices + "</html>", encoding="utf-8")
    (site / ".nojekyll").touch()
    print(f"Prepared GMapHUD {version} at {URL}; package SHA256 {hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    main()
