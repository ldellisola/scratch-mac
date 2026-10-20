#!/usr/bin/env python3
"""Give the screenshots that `xcresulttool export attachments` wrote their real names.

    name-screenshots.py <exported-dir> <out-dir> <name>...

`xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <exported-dir>` writes every attachment
under a generated file name, and a manifest.json that says which attachment belongs to which test: a list of
`{"testIdentifier", "attachments": [{"exportedFileName", "suggestedHumanReadableName", ...}]}`. ScreenshotTests attach
each screenshot with `name = <name>`, and Xcode suggests `<name>_<index>_<UUID>.<extension>` for it.

This copies the file of each expected <name> to <out-dir>/<name>.png. An attachment is matched by the name in its
suggested file name, or else by its test: `ScreenshotTests/testHugeNoteLight()` is `huge-note-light`. A file that is
not a PNG is converted with `sips` (macOS). Attachments that match no expected name are left alone.

Exit: 0 every expected name was written, 1 some are missing (the manifest is printed to help), 64 usage error.
Standard library only.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

# <name>_<index>_<UUID>.<extension>, or just <name>.<extension>.
SUGGESTED_NAME = re.compile(r"^(?P<name>.+?)(?:_\d+_[0-9A-Fa-f-]{36})?\.(?P<extension>[A-Za-z0-9]+)$")
IMAGE_EXTENSIONS = {"png", "heic", "jpg", "jpeg", "tiff"}


def name_from_attachment(suggested: str) -> str | None:
    match = SUGGESTED_NAME.match(suggested)
    return match.group("name") if match else None


def name_from_test(identifier: str) -> str | None:
    """`ScreenshotTests/testHugeNoteLight()` -> `huge-note-light`."""
    method = identifier.rsplit("/", 1)[-1].removesuffix("()").removeprefix("test")
    words = re.findall(r"[A-Z][a-z0-9]*|[a-z0-9]+", method)
    return "-".join(word.lower() for word in words) or None


def manifest_entries(manifest: object) -> list[dict]:
    if isinstance(manifest, dict):
        manifest = manifest.get("tests") or manifest.get("attachments") or []
    return [entry for entry in manifest if isinstance(entry, dict)]


def write_png(source: Path, destination: Path) -> None:
    if source.suffix.lower() == ".png":
        shutil.copyfile(source, destination)
    else:
        subprocess.run(["sips", "-s", "format", "png", str(source), "--out", str(destination)], check=True)


def name_screenshots(exported: Path, out: Path, expected: list[str]) -> list[str]:
    """Writes <out>/<name>.png for what it can and returns the expected names that are still missing."""
    manifest = json.loads((exported / "manifest.json").read_text(encoding="utf-8"))
    # Every exported image: (name its test implies, name its file implies, file, suggested name).
    images = []
    for entry in manifest_entries(manifest):
        test_name = name_from_test(str(entry.get("testIdentifier", "")))
        for attachment in entry.get("attachments", []):
            suggested = str(attachment.get("suggestedHumanReadableName", ""))
            exported_name = str(attachment.get("exportedFileName", ""))
            source = exported / exported_name
            if exported_name and source.is_file() and source.suffix.lstrip(".").lower() in IMAGE_EXTENSIONS:
                images.append((test_name, name_from_attachment(suggested), source, suggested))

    out.mkdir(parents=True, exist_ok=True)
    written: set[str] = set()
    used: set[Path] = set()

    def write(name: str, source: Path, suggested: str) -> None:
        write_png(source, out / f"{name}.png")
        written.add(name)
        used.add(source)
        print(f"{name}.png <- {source.name} ({suggested})")

    # An attachment's own name wins. Only then does a test's name stand in for an attachment that has none.
    for _, attachment_name, source, suggested in images:
        if attachment_name in expected and attachment_name not in written:
            write(attachment_name, source, suggested)
    for test_name, _, source, suggested in images:
        if test_name in expected and test_name not in written and source not in used:
            write(test_name, source, suggested)
    return [name for name in expected if name not in written]


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        print("usage: name-screenshots.py <exported-dir> <out-dir> <name>...", file=sys.stderr)
        return 64
    exported, out, expected = Path(argv[1]), Path(argv[2]), argv[3:]
    try:
        missing = name_screenshots(exported, out, expected)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"name-screenshots.py: {error}", file=sys.stderr)
        missing = list(expected)
    if missing:
        print(f"name-screenshots.py: no screenshot found for: {', '.join(missing)}", file=sys.stderr)
        manifest = exported / "manifest.json"
        if manifest.is_file():
            print(f"--- {manifest}", file=sys.stderr)
            print(manifest.read_text(encoding="utf-8"), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
