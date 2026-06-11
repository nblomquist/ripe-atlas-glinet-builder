#!/usr/bin/env python3
"""Rewrite one dependency token in an OpenWrt package control file."""

from pathlib import Path
import re
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: rewrite-control-dependency.py CONTROL_FILE OLD_DEP NEW_DEP",
            file=sys.stderr,
        )
        return 2

    control_path = Path(sys.argv[1])
    old_dep = sys.argv[2]
    new_dep = sys.argv[3]

    text = control_path.read_text()
    lines = text.splitlines()
    out = []
    changed = False
    i = 0

    dep_pattern = re.compile(
        rf"(?<![A-Za-z0-9_.+-]){re.escape(old_dep)}(?![A-Za-z0-9_.+-])"
    )

    while i < len(lines):
        line = lines[i]
        if line.startswith("Depends:"):
            field_lines = [line]
            i += 1
            while i < len(lines) and (
                lines[i].startswith(" ") or lines[i].startswith("\t")
            ):
                field_lines.append(lines[i])
                i += 1
            field = "\n".join(field_lines)
            new_field = dep_pattern.sub(new_dep, field)
            if new_field != field:
                changed = True
            out.extend(new_field.splitlines())
            continue
        out.append(line)
        i += 1

    if not changed:
        print(
            f"ERROR: did not find dependency token {old_dep!r} in Depends field",
            file=sys.stderr,
        )
        return 1

    control_path.write_text("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
