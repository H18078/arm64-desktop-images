#!/usr/bin/env python3
"""What an image is made from, as one hash: its script, the shared steps and
the container they run in, and its own folder (build/ID/) if it has one. Its
vendor-data isn't part of it: that goes in the catalog, not the disk.

    build/recipe.py ID
"""
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def recipe(image):
    paths = [f"{image}.sh", "lib.sh", "in-container.sh"]
    folder = os.path.join(HERE, image)
    if os.path.isdir(folder):
        for top, _, files in os.walk(folder):
            paths += [os.path.relpath(os.path.join(top, name), HERE) for name in files]
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.encode() + b"\0")
        with open(os.path.join(HERE, path), "rb") as f:
            digest.update(f.read())
        digest.update(b"\0")
    return digest.hexdigest()


if __name__ == "__main__":
    print(recipe(sys.argv[1]))
