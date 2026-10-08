#!/usr/bin/env python3
"""Print the Python dependencies that a TOML manifest gained between two versions.

Usage: new_python_deps.py BASE_FILE HEAD_FILE

Works for pyproject.toml and Pipfile. Only dependency tables are read, so a config
key such as coverage's ``omit`` or ruff's ``exclude`` is never mistaken for a package
(that false positive blocked a real PR). BASE_FILE may be empty or missing when the
manifest is new. One package name per line, lower-cased, sorted.

Exit 0 on success. Exit 3 when no TOML parser is available (Python < 3.11 without
``tomli``), so the caller can fail open with a warning.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover - old runners
    try:
        import tomli as tomllib  # type: ignore[no-redef]
    except ModuleNotFoundError:
        sys.stderr.write("new_python_deps: no TOML parser (need Python 3.11+ or tomli)\n")
        sys.exit(3)

# PEP 508 project name: the leading name token of a requirement string.
NAME = re.compile(r"^\s*([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)")

# Poetry's own interpreter pin is not a package.
SKIP_KEYS = {"python"}


def names_from_list(items: Any) -> set[str]:
    """Requirement strings like ``"requests>=2 ; python_version>'3.8'"``."""
    found: set[str] = set()
    if not isinstance(items, list):
        return found
    for item in items:
        if isinstance(item, str):
            match = NAME.match(item)
            if match:
                found.add(match.group(1).lower())
    return found


def names_from_table(table: Any) -> set[str]:
    """Poetry / Pipfile style: ``requests = "^2.0"`` or ``requests = {version = "*"}``."""
    if not isinstance(table, dict):
        return set()
    return {key.lower() for key in table if key.lower() not in SKIP_KEYS}


def dependency_names(doc: dict[str, Any]) -> set[str]:
    found: set[str] = set()
    project = doc.get("project", {})
    found |= names_from_list(project.get("dependencies"))
    for group in (project.get("optional-dependencies") or {}).values():
        found |= names_from_list(group)
    for group in (doc.get("dependency-groups") or {}).values():
        found |= names_from_list(group)  # dict entries like {include-group = ...} are skipped
    found |= names_from_list((doc.get("build-system") or {}).get("requires"))

    tool = doc.get("tool") or {}
    poetry = tool.get("poetry") or {}
    found |= names_from_table(poetry.get("dependencies"))
    found |= names_from_table(poetry.get("dev-dependencies"))
    for group in (poetry.get("group") or {}).values():
        found |= names_from_table((group or {}).get("dependencies"))
    found |= names_from_list((tool.get("uv") or {}).get("dev-dependencies"))
    for group in ((tool.get("pdm") or {}).get("dev-dependencies") or {}).values():
        found |= names_from_list(group)

    # Pipfile
    found |= names_from_table(doc.get("packages"))
    found |= names_from_table(doc.get("dev-packages"))
    return found


def load(path: str) -> dict[str, Any]:
    """The parsed manifest, or ``{}`` when the file is missing, empty or not valid TOML."""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError:
        return {}
    if not text.strip():
        return {}
    try:
        return tomllib.loads(text)
    except (tomllib.TOMLDecodeError, UnicodeDecodeError) as exc:
        sys.stderr.write(f"new_python_deps: {path}: {exc}\n")
        return {}


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        sys.stderr.write(__doc__ or "")
        return 2
    base, head = load(argv[1]), load(argv[2])
    added = sorted(dependency_names(head) - dependency_names(base))
    sys.stdout.write("".join(f"{name}\n" for name in added))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
