#!/usr/bin/env python3
"""Which images a release has to build: those whose recipe isn't the one the
previous release built them from, or every one of them. The rest are reused
from where they already are.

    build/plan.py changed|all PREVIOUS_CATALOG ID... > plan.json
"""
import json
import sys

from recipe import recipe

mode, previous_path, images = sys.argv[1], sys.argv[2], sys.argv[3:]
previous = {image["id"]: image for image in json.load(open(previous_path)).get("images", [])}

build = [image for image in images
         if mode == "all" or previous.get(image, {}).get("recipe") != recipe(image)]
json.dump({"build": build, "reuse": [image for image in images if image not in build]}, sys.stdout)
print()
