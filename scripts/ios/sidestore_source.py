#!/usr/bin/env python3
"""Writes the AltStore/SideStore source for the Vela iOS distribution branch.

Usage: sidestore_source.py <dist dir> <base raw URL> [release notes]
The dist dir contains Vela.ipa and icon.png. Only the latest IPA is kept: the branch is
force-pushed as one commit by publish-sidestore.sh.
"""
import json
import plistlib
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path


def main() -> None:
    dist = Path(sys.argv[1])
    base = sys.argv[2].rstrip("/")
    notes = sys.argv[3] if len(sys.argv) > 3 else "Latest Vela iOS development build."
    ipa = dist / "Vela.ipa"
    with zipfile.ZipFile(ipa) as z:
        plist_names = [n for n in z.namelist() if n.startswith("Payload/") and n.endswith(".app/Info.plist")]
        if len(plist_names) != 1:
            raise SystemExit(f"expected one app Info.plist, got {plist_names}")
        info = plistlib.loads(z.read(plist_names[0]))
    bundle = info["CFBundleIdentifier"]
    version = info["CFBundleShortVersionString"]
    build = str(info.get("CFBundleVersion", ""))
    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    description = (
        "Vela is a privacy-minded maps app: search, place details, routes, guided navigation, "
        "saved places and offline regions.\n\n"
        "Development build distributed unsigned for AltStore, SideStore or Sideloadly. "
        "The app and its navigation Live Activity extension must be signed together."
    )
    download = f"{base}/Vela.ipa"
    version_entry = {
        "version": version,
        "buildVersion": build,
        "date": now,
        "localizedDescription": f"{notes}\n\nBuild {build}." if build else notes,
        "downloadURL": download,
        "size": ipa.stat().st_size,
        "minOSVersion": info.get("MinimumOSVersion", "17.0"),
    }
    source = {
        "name": "Vela iOS",
        "identifier": "app.vela.ios.source",
        "sourceURL": f"{base}/apps.json",
        "subtitle": "Vela maps, development builds",
        "description": "Development builds of the Vela iOS port. Install and update through SideStore or AltStore.",
        "iconURL": f"{base}/icon.png",
        "website": "https://github.com/PimpinPumpkin/Vela",
        "tintColor": "#0A8F83",
        "nsfw": False,
        "featuredApps": [bundle],
        "apps": [
            {
                "name": "Vela",
                "bundleIdentifier": bundle,
                "developerName": "Vela contributors",
                "subtitle": "Maps, navigation and offline regions",
                "localizedDescription": description,
                "iconURL": f"{base}/icon.png",
                "tintColor": "#0A8F83",
                "screenshots": [f"{base}/screenshot.png"],
                "screenshotURLs": [f"{base}/screenshot.png"],
                "category": "utilities",
                "versions": [version_entry],
                # AltStore Classic / older SideStore compatibility.
                "version": version,
                "versionDate": now,
                "versionDescription": version_entry["localizedDescription"],
                "downloadURL": download,
                "size": version_entry["size"],
                "appPermissions": {
                    "entitlements": [],
                    "privacy": {
                        key: str(value)
                        for key, value in info.items()
                        if key.endswith("UsageDescription")
                    },
                },
            }
        ],
        "news": [],
    }
    (dist / "apps.json").write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n")
    print(f"SideStore source: {version} ({build}), {version_entry['size']} bytes")


if __name__ == "__main__":
    main()
