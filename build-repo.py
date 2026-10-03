#!/usr/bin/env python3
"""Publish an existing GMapHUD package into the static Sileo source."""
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
SILEO_DEPICTION_URL = URL + "sileo-depiction.json"
SCREENSHOTS = (
    URL + "screenshots/gmaphud-full-map-f7c79e32.png",
    URL + "screenshots/gmaphud-dashboard.png",
)


def build_sileo_depiction():
    screenshots = {
        "vi": [
            "Bản đồ CarPlay đầy đủ: trạng thái bình thường, 15/50 km/h; tuyến giả lập.",
            "Dashboard CarPlay: trạng thái vượt giới hạn, 74/50 km/h; tuyến giả lập.",
        ],
        "en": [
            "Full-map CarPlay: normal state at 15/50 km/h; simulated route.",
            "CarPlay Dashboard: overspeed state at 74/50 km/h; simulated route.",
        ],
    }
    copy = {
        "vi": {
            "tab": "Tiếng Việt",
            "title": "GMapHUD trên CarPlay",
            "intro": (
                "Hiển thị tốc độ hiện tại và giới hạn từ VietMap Live trong Google Maps CarPlay. "
                "Google Maps tiếp tục đảm nhiệm việc dẫn đường."
            ),
            "screenshots": "Ảnh xem trước · CarPlay Simulator",
            "compatibility": "Thiết lập đã kiểm thử",
            "compatibility_text": (
                "iPhone 11 · iOS 18.6.2 rootless · Google Maps 26.39.0 "
                "(executable UUID phải khớp README) · VietMap Live 3.4.2."
            ),
            "safety": "Phạm vi và lưu ý",
            "safety_text": (
                "Ảnh dùng tuyến giả lập; không chứng minh độ chính xác ngoài đường thực tế. "
                "Dữ liệu có thể sai, trễ hoặc thiếu. Chỉ dùng để nghiên cứu/kiểm thử khi xe đã đỗ an toàn; "
                "tuân thủ biển báo thực tế. Không phải thiết bị hỗ trợ lái xe được chứng nhận.\n\n"
                "Chỉ hiển thị tốc độ và giới hạn; không có biển báo khác, cảnh báo âm thanh, giả lập GPS "
                "hay vượt thuê bao/DRM. Mã nguồn theo giấy phép MIT. Dự án độc lập, không được "
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
            "title": "GMapHUD on CarPlay",
            "intro": (
                "Displays current speed and limits from VietMap Live in Google Maps CarPlay. "
                "Google Maps continues to handle navigation."
            ),
            "screenshots": "Previews · CarPlay Simulator",
            "compatibility": "Tested setup",
            "compatibility_text": (
                "iPhone 11 · iOS 18.6.2 rootless · Google Maps 26.39.0 "
                "(executable UUID must match the README) · VietMap Live 3.4.2."
            ),
            "safety": "Scope and safety",
            "safety_text": (
                "Screenshots use a simulated route; they do not establish real-road accuracy. "
                "Readings may be wrong, delayed, or missing. For research and stationary testing only; "
                "follow actual signs. This is not a certified driving aid.\n\n"
                "Speed and limits only; no other signs, audible alerts, GPS simulation, or subscription/DRM "
                "bypass. Source is MIT-licensed. Independent project, not endorsed by VietMap, Google, or Apple."
            ),
            "links": "Links",
            "links_text": (
                f"[Project website]({URL}) · [GitHub](https://github.com/bechou0410/gmaphud) · "
                f"[Disclaimer]({URL}notices.html#en)"
            ),
        },
    }
    changelog = (
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


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 build-repo.py path/to/gmaphud.deb")
    package = Path(sys.argv[1]).resolve(strict=True)
    control = subprocess.check_output(["dpkg-deb", "--field", str(package)], text=True).strip()
    fields = dict(re.findall(r"^([A-Za-z][A-Za-z0-9-]*): (.*)$", control, re.MULTILINE))
    if fields.get("Package") != "com.chou.googlemaps.vietmap" or fields.get("Architecture") != "iphoneos-arm64":
        raise SystemExit("Only the GMapHUD rootless package is allowed.")
    version = fields["Version"]
    if not re.fullmatch(r"[A-Za-z0-9.+:~\-]+", version):
        raise SystemExit("Invalid package version.")
    name = f"com.chou.googlemaps.vietmap_{version}_iphoneos-arm64.deb"
    site = ROOT / "docs"
    pool = site / "pool"
    pool.mkdir(parents=True, exist_ok=True)
    target = pool / name
    data = package.read_bytes()
    if target.exists() and target.read_bytes() != data:
        raise SystemExit("Published package versions are immutable; bump the version first.")
    if package != target:
        shutil.copyfile(package, target)
    stanza = control + "\n" + f"Filename: pool/{name}\nSize: {len(data)}\n"
    for field, algorithm in (("MD5sum", "md5"), ("SHA1", "sha1"), ("SHA256", "sha256"), ("SHA512", "sha512")):
        stanza += f"{field}: {hashlib.new(algorithm, data).hexdigest()}\n"
    stanza += f"Depiction: {URL}\nSileoDepiction: {SILEO_DEPICTION_URL}\n"
    stanza += "Homepage: https://github.com/bechou0410/gmaphud\n"
    stanza += "Bugs: https://github.com/bechou0410/gmaphud/issues\n"
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
        "Origin: GMapHUD\nLabel: GMapHUD\nSuite: experimental\nCodename: gmaphud\n"
        "Version: 1\nArchitectures: iphoneos-arm64\nComponents: main\n"
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
        values = {**locales[language], "LANG": language, "VERSION": version, "REPO_URL": URL,
                  "PACKAGE_PATH": "pool/" + name, "VI_CURRENT": "page" if language == "vi" else "false",
                  "EN_CURRENT": "page" if language == "en" else "false"}
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
