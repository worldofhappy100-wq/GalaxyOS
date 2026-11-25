#!/usr/bin/env python3
"""Build the catalog and optional offline package tree from versioned source."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME_HUB_VERSION = "1.0.0"
VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+\Z", re.ASCII)
FILE_PATTERN = re.compile(r"[a-z0-9_-]+\.[a-z]+\Z")
ORIGIN = "https://raw.githubusercontent.com/worldofhappy100-wq/GalaxyOS/main/"
APPS = {
    "tasks": ("Tasks", "View, focus and restart running windows."),
    "devices": ("Device Manager", "Peripheral diagram and Minecraft / Create controls."),
    "network": ("Network", "Find Galaxy computers, send files and join rooms."),
    "games": ("Games", "Launch installed arcade games locally or over rednet."),
    "navigation": ("Navigation", "GPS, coordinates, saved waypoints and a zoomable map."),
    "robotics": ("Robotics", "Discover and operate paired Minecraft turtles."),
    "paint": ("Paint", "Edit and save sixteen-color pixel drawings."),
    "gallery": ("Gallery", "Browse saved drawings and set an image as wallpaper."),
}
GAMES = {
    "game2048": ("2048", "Combine tiles in the classic four-by-four puzzle."),
    "minesweeper": ("Minesweeper", "Find safe cells and mark the hidden mines."),
    "breakout": ("Breakout", "Clear bricks with the paddle and ball."),
}


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=True) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true")
    args = parser.parse_args()
    catalog = []
    for category, listing in (("apps", APPS), ("games", GAMES)):
        for package_id, (name, description) in listing.items():
            source = ROOT / category / package_id
            candidates = [item for item in source.iterdir()
                          if VERSION_PATTERN.fullmatch(item.name) and (item / "main.lua").is_file()]
            folder = max(candidates, key=lambda item: tuple(map(int, item.name.split("."))))
            version = folder.name
            package = folder.relative_to(ROOT)
            files = []
            for item in sorted(folder.iterdir()):
                if item.is_file() and item.name != "manifest.json" and FILE_PATTERN.fullmatch(item.name):
                    data = item.read_bytes()
                    files.append(dict(path=item.name, bytes=len(data),
                        sha256=hashlib.sha256(data).hexdigest(), url=ORIGIN + (package / item.name).as_posix()))
            metadata = dict(id=package_id, version=version, name=name, description=description,
                icon=package_id if category == "apps" else "games", category=category,
                kind="app" if category == "apps" else "engine",
                dependencies=[] if category == "apps" else [dict(id="games", version=GAME_HUB_VERSION)],
                bytes=sum(file["bytes"] for file in files), files=files)
            catalog.append(metadata)
            write_json(folder / "manifest.json", metadata)
            if args.offline:
                dest = ROOT / "galaxy/packages" / package_id
                dest.mkdir(parents=True, exist_ok=True)
                for file in [item["path"] for item in files] + ["manifest.json"]:
                    shutil.copyfile(folder / file, dest / file)
    write_json(ROOT / "catalog.json", dict(schema=1, packages=catalog))
    if args.offline or (ROOT / "galaxy").is_dir():
        write_json(ROOT / "galaxy/catalog.json", dict(schema=1, packages=catalog))


if __name__ == "__main__":
    main()
