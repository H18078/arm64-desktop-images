#!/usr/bin/env python3
"""The catalog of a release: every image, in the order given, with download
URLs. An image this release built (its ID.json in DIR) points at this
release's files; any other is the previous catalog's entry, pointing at the
release that built it, as reused or because its build failed this time.
Either way its vendor-data is the current one.

    build/catalog.py TAG DIR PREVIOUS_CATALOG ID... > catalog.json
"""
import datetime
import json
import os
import sys

from recipe import HERE, recipe

tag, folder, previous_path, ids = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
repository = os.environ.get("GITHUB_REPOSITORY", "oneamendez/arm64-desktop-images")
base = f"https://github.com/{repository}/releases/download/{tag}"
previous = {image["id"]: image for image in json.load(open(previous_path)).get("images", [])}
today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()


def located(entry):
    return {**entry, "url": f"{base}/{entry['file']}"}


images = []
for id_ in ids:
    built = os.path.join(folder, f"{id_}.json")
    if os.path.exists(built):
        image = json.load(open(built))
        image["kernel"] = located(image["kernel"])
        image["initrd"] = located(image["initrd"])
        image["disk"]["parts"] = [located(part) for part in image["disk"]["parts"]]
        image.update(release=tag, built=today, recipe=recipe(id_))
    elif id_ in previous:
        image = previous[id_]
        print(f"catalog: {id_} from {image.get('release', 'an earlier release')}", file=sys.stderr)
    else:
        print(f"catalog: {id_} wasn't built and no earlier release has it; left out", file=sys.stderr)
        continue
    vendor_data = os.path.join(HERE, "vendor-data", f"{id_}.yaml")
    if os.path.exists(vendor_data):
        image["vendorData"] = open(vendor_data).read()
    else:
        image.pop("vendorData", None)
    images.append(image)

json.dump({"format": 1, "release": tag, "images": images}, sys.stdout, indent=2)
print()
