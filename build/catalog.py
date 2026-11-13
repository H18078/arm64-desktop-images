#!/usr/bin/env python3
"""The catalog of a release: every image's ID.json, with download URLs.

    build/catalog.py TAG DIR > catalog.json
"""
import json
import os
import sys

tag, folder = sys.argv[1], sys.argv[2]
repository = os.environ.get("GITHUB_REPOSITORY", "oneamendez/arm64-desktop-images")
base = f"https://github.com/{repository}/releases/download/{tag}"


def located(entry):
    return {**entry, "url": f"{base}/{entry['file']}"}


images = []
for name in sorted(os.listdir(folder)):
    if not name.endswith(".json"):
        continue
    image = json.load(open(os.path.join(folder, name)))
    image["kernel"] = located(image["kernel"])
    image["initrd"] = located(image["initrd"])
    image["disk"]["parts"] = [located(part) for part in image["disk"]["parts"]]
    images.append(image)

json.dump({"format": 1, "release": tag, "images": images}, sys.stdout, indent=2)
print()
