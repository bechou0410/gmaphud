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
    stanza += f"Depiction: {URL}\nHomepage: https://github.com/bechou0410/gmaphud\n"
    stanza += "Bugs: https://github.com/bechou0410/gmaphud/issues\n"
    indexes = {"Packages": stanza.encode()}
    indexes["Packages.gz"] = gzip.compress(indexes["Packages"], mtime=0)
    indexes["Packages.bz2"] = bz2.compress(indexes["Packages"])
    indexes["Packages.xz"] = lzma.compress(indexes["Packages"])
    for filename, content in indexes.items():
        (site / filename).write_bytes(content)
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
