#!/usr/bin/env python3
"""Make App/Resources/Acknowledgements.rtf: the licences of tree-sitter and of every grammar in the build.

    scripts/make-acknowledgements.py [--root DIR] [--output FILE] [--check]

The About panel shows the file (`AboutCredits`), and `scripts/check-release-zip.sh` fails a release that lacks it. Every
component of the build is listed under a heading with its version and where it is from, followed by the text of its LICENSE
file, so a new grammar adds itself: run this script after adding it and check the new file in
(docs/decisions/0007-tree-sitter.md, "Adding a language").

Where the components come from (all under `<root>/Packages/ScratchCode`):

  - Package.resolved: every package that SwiftPM resolves (the tree-sitter runtime, swift-tree-sitter and the grammars that
    are dependencies), with its exact version. The LICENSE file of each is the one SwiftPM checked out into
    `.build/checkouts/<identity>/`, so run `swift package --package-path Packages/ScratchCode resolve` (or `make core-test`)
    first.
  - Sources/Grammar*/: the grammars that are vendored. Each folder has the grammar's LICENSE and a README.md that names its
    repository (an https://github.com/ URL) and its tag (``at tag `v1.2.3` ``) or its commit (``at commit `abc...` ``).

The output is deterministic: components are in alphabetical order, and nothing in it depends on the date or the machine.

`--check` does not write. It exits 0 when the file is current and 1 when it is not, naming what is wrong. With the LICENSE
files at hand it compares the whole file. Without the SwiftPM checkouts it can only see that every component is in the file
under its name and version, and says that it did not compare the licence texts.

Exit: 0 fine, 1 `--check` found the file out of date, 2 something it needs is missing (named on stderr).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

LICENCE_FILE_NAMES = ("LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "LICENCE.md", "LICENCE.txt", "COPYING")
PACKAGE_DIRECTORY = Path("Packages/ScratchCode")
DEFAULT_OUTPUT = Path("App/Resources/Acknowledgements.rtf")
INSTALL_HINT = "run `swift package --package-path Packages/ScratchCode resolve` (or `make core-test`) to fetch them"

INTRODUCTION = (
    "Scratch colours code with tree-sitter and its grammars. Each of the following is used under its own licence, "
    "which is reproduced in full below its name. The highlight queries that Scratch carries are copies of those of "
    "the grammars, with the changes that docs/decisions/0007-tree-sitter.md lists, and are under the licence of "
    "their grammar."
)


class MissingInput(Exception):
    """Something the generator reads is not there. The message says what and, where it can, how to get it."""


@dataclass(frozen=True)
class Component:
    name: str
    version: str
    url: str
    #: The LICENSE file, or None when it is not there (the checkout has not been made).
    licence_file: Path | None
    #: Where the licence was expected, for the message when it is missing.
    expected_at: Path

    @property
    def heading(self) -> str:
        return f"{self.name} {self.version}"


# --- Reading the build -------------------------------------------------------------------------------------------------


def find_licence(directory: Path) -> Path | None:
    """The LICENSE file in `directory`, whatever its spelling, or None."""
    for name in LICENCE_FILE_NAMES:
        candidate = directory / name
        if candidate.is_file():
            return candidate
    return None


def read_pins(package_directory: Path) -> list[dict]:
    resolved = package_directory / "Package.resolved"
    if not resolved.is_file():
        raise MissingInput(f"{resolved} does not exist: it lists the packages whose licences are reproduced")
    try:
        data = json.loads(resolved.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise MissingInput(f"{resolved} cannot be read: {error}") from error
    pins = data.get("pins")
    if pins is None and isinstance(data.get("object"), dict):  # Package.resolved version 1
        pins = [
            {
                "identity": pin.get("package", "").lower(),
                "location": pin.get("repositoryURL", ""),
                "state": pin.get("state", {}),
            }
            for pin in data["object"].get("pins", [])
        ]
    if pins is None:
        raise MissingInput(f"{resolved} has no pins")
    return pins


def package_components(package_directory: Path) -> list[Component]:
    components = []
    for pin in read_pins(package_directory):
        identity = pin["identity"]
        state = pin.get("state", {})
        version = state.get("version") or state.get("branch") or (state.get("revision") or "unknown")[:7]
        url = re.sub(r"\.git$", "", pin.get("location", ""))
        checkout = package_directory / ".build" / "checkouts" / identity
        components.append(
            Component(
                name=identity,
                version=version,
                url=url,
                licence_file=find_licence(checkout),
                expected_at=checkout / "LICENSE",
            )
        )
    return components


def vendored_components(package_directory: Path) -> list[Component]:
    components = []
    for folder in sorted((package_directory / "Sources").glob("Grammar*")):
        if not folder.is_dir():
            continue
        readme = folder / "README.md"
        text = readme.read_text(encoding="utf-8") if readme.is_file() else ""
        url_match = re.search(r"https://github\.com/[\w.-]+/[\w.-]+", text)
        if url_match is None:
            raise MissingInput(
                f"{readme} must say where the grammar is from: an https://github.com/<owner>/<repository> URL"
            )
        url = url_match.group(0).rstrip(".")
        tag = re.search(r"at\s+tag\s+`([^`]+)`", text)
        commit = re.search(r"at\s+commit\s+`([0-9a-f]{7,40})`", text)
        if tag:
            version = tag.group(1)
        elif commit:
            version = "commit " + commit.group(1)[:7]
        else:
            raise MissingInput(f"{readme} must name the tag (at tag `v1.2.3`) or the commit (at commit `abc...`)")
        licence = find_licence(folder)
        if licence is None:
            raise MissingInput(f"{folder} has no LICENSE: a vendored grammar carries its own")
        components.append(
            Component(name=url.rsplit("/", 1)[-1], version=version, url=url, licence_file=licence, expected_at=licence)
        )
    return components


def all_components(root: Path) -> list[Component]:
    package_directory = root / PACKAGE_DIRECTORY
    components = package_components(package_directory) + vendored_components(package_directory)
    return sorted(components, key=lambda component: (component.name.casefold(), component.version))


# --- The licences ------------------------------------------------------------------------------------------------------


def licence_kind(text: str) -> str | None:
    """The name of a licence that the text is one of, or None when it is not one of those that are known."""
    flat = " ".join(text.split()).lower()
    if "permission is hereby granted, free of charge" in flat:
        return "MIT"
    if "redistribution and use in source and binary forms" in flat:
        return "BSD 3-Clause" if "neither the name" in flat else "BSD 2-Clause"
    if "apache license" in flat and "version 2.0" in flat:
        return "Apache 2.0"
    return None


COPYRIGHT_LINE = re.compile(r"copyright\s*(\(c\)|\u00a9)", re.IGNORECASE)


def paragraphs(text: str) -> list[str]:
    """The paragraphs of a licence text: its lines are wrapped for a terminal, so they are joined, and a blank line ends one."""
    result: list[str] = []
    current: list[str] = []
    for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if line.strip() and COPYRIGHT_LINE.match(line.strip()) and current:
            # Each holder has a line of their own, also when no blank line is between two of them.
            result.append(" ".join(current))
            current = []
        if line.strip():
            current.append(line.strip())
        elif current:
            result.append(" ".join(current))
            current = []
    if current:
        result.append(" ".join(current))
    return result


# --- RTF ---------------------------------------------------------------------------------------------------------------


def rtf_escape(text: str) -> str:
    """`text` as RTF: 7-bit, with the three characters that mean something escaped and the rest as unicode escapes."""
    out: list[str] = []
    for character in text:
        code = ord(character)
        if character in "\\{}":
            out.append("\\" + character)
        elif character == "\t":
            out.append("\\tab ")
        elif code < 32 or code == 127:
            out.append(" ")
        elif code < 128:
            out.append(character)
        else:
            encoded = character.encode("utf-16-le")
            for index in range(0, len(encoded), 2):
                unit = int.from_bytes(encoded[index : index + 2], "little")
                out.append(f"\\u{unit - 65536 if unit > 32767 else unit}?")
    return "".join(out)


BODY = "\\pard\\plain\\f0\\fs18"


def render(components: list[Component]) -> str:
    """The text of Acknowledgements.rtf for `components`, every one of which has its licence file."""
    lines = [
        "{\\rtf1\\ansi\\ansicpg1252\\deff0",
        "{\\fonttbl{\\f0\\fswiss\\fcharset0 Helvetica;}}",
        "\\pard\\plain\\f0\\b\\fs28\\sa160 Acknowledgements\\par",
        f"{BODY}\\sa160 {rtf_escape(INTRODUCTION)}\\par",
    ]
    for component in components:
        assert component.licence_file is not None
        text = component.licence_file.read_text(encoding="utf-8", errors="replace")
        kind = licence_kind(text)
        lines.append(f"\\pard\\plain\\f0\\sb240\\sa40 {{\\b\\fs20 {rtf_escape(component.heading)}}}\\par")
        lines.append(f"{BODY}\\sa40 {rtf_escape(component.url)}\\par")
        lines.append(f"{BODY}\\sa100 {rtf_escape((kind + ' licence') if kind else 'Licence')}\\par")
        for paragraph in paragraphs(text):
            lines.append(f"{BODY}\\sa100 {rtf_escape(paragraph)}\\par")
    lines.append("}")
    return "\n".join(lines) + "\n"


# --- Commands ----------------------------------------------------------------------------------------------------------


def missing_licences(components: list[Component]) -> list[Component]:
    return [component for component in components if component.licence_file is None]


def generate(root: Path, output: Path) -> int:
    components = all_components(root)
    missing = missing_licences(components)
    if missing:
        names = "\n".join(f"  {component.name}: {component.expected_at} does not exist" for component in missing)
        raise MissingInput(f"no LICENSE for {len(missing)} package(s):\n{names}\n{INSTALL_HINT}")
    text = render(components)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(text.encode("ascii"))
    print(f"make-acknowledgements.py: wrote {output} ({len(components)} components)")
    return 0


def check(root: Path, output: Path) -> int:
    components = all_components(root)
    if not output.is_file():
        print(
            f"make-acknowledgements.py: {output} does not exist: run scripts/make-acknowledgements.py and check it in",
            file=sys.stderr,
        )
        return 1
    try:
        current = output.read_bytes().decode("ascii")
    except UnicodeDecodeError:
        current = ""
    if not missing_licences(components):
        if render(components) == current:
            print(f"make-acknowledgements.py: {output.name} is up to date ({len(components)} components)")
            return 0
        print(
            f"make-acknowledgements.py: {output} is out of date: run scripts/make-acknowledgements.py and check it in",
            file=sys.stderr,
        )
        return 1
    absent = [component.heading for component in components if component.heading not in current]
    if absent:
        print(
            f"make-acknowledgements.py: {output} lacks {', '.join(absent)}: "
            "run scripts/make-acknowledgements.py and check it in",
            file=sys.stderr,
        )
        return 1
    print(
        f"make-acknowledgements.py: {output.name} names every component with its version "
        f"({len(components)} components); the licence texts were not compared, because the SwiftPM checkouts are "
        f"missing ({INSTALL_HINT})"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Make App/Resources/Acknowledgements.rtf from the licences of the build.")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent, help="the repository root")
    parser.add_argument("--output", type=Path, help=f"the file to write (default: <root>/{DEFAULT_OUTPUT})")
    parser.add_argument("--check", action="store_true", help="do not write: exit 1 when the file is out of date")
    arguments = parser.parse_args()
    root = arguments.root
    output = arguments.output or root / DEFAULT_OUTPUT
    try:
        return check(root, output) if arguments.check else generate(root, output)
    except MissingInput as error:
        print(f"make-acknowledgements.py: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
