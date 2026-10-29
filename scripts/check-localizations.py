#!/usr/bin/env python3
"""Check localization key parity and literal MoaL10n references in app sources."""
import json
from pathlib import Path
import re
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parent.parent
    tables = {}
    for language in ("en", "zh-Hans"):
        path = root / "assets/Localization" / f"{language}.lproj/Localizable.strings"
        tables[language] = json.loads(subprocess.check_output(
            ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(path)], text=True))
    errors = []
    all_keys = set().union(*(set(table) for table in tables.values()))
    for language, table in tables.items():
        for key in sorted(all_keys - table.keys()):
            errors.append(f"{language}: missing localization key {key!r}")
    literal = re.compile(r'MoaL10n\.(?:text|format)\(\s*("(?:[^"\\]|\\.)*")')
    for path in sorted((root / "macos-menu-bar").glob("*.swift")):
        source = path.read_text()
        for match in literal.finditer(source):
            # Interpolated strings are not stable keys; only validate literal keys here.
            if "\\(" in match[1]:
                continue
            key = json.loads(match[1])
            missing = [language for language, table in tables.items() if key not in table]
            if missing:
                line = source.count("\n", 0, match.start()) + 1
                errors.append(f"{path.name}:{line}: key absent in {', '.join(missing)}: {key!r}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"PASS: localization keys match ({len(all_keys)} keys); literal app references are covered")
    return 0


if __name__ == "__main__":
    sys.exit(main())
