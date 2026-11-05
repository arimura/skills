#!/usr/bin/env python3
"""Validate skills and package each one as a ZIP for upload to claude.ai.

Usage:
    python3 tools/package_skills.py [skill-name ...]

With no arguments, every directory under skills/ is packaged. Output goes to
dist/<skill-name>.zip, one skill per ZIP. claude.ai accepts one skill per upload,
and expects the ZIP to hold the skill folder at its root:

    <skill-name>.zip
    └── <skill-name>/
        ├── SKILL.md
        └── (any supporting files)

Checks (from the claude.ai custom-skill requirements):
    - SKILL.md exists and starts with YAML frontmatter
    - `name` is present, matches the folder name, and is at most 64 characters
    - `description` is present and at most 200 characters
Exits 1 if any skill fails validation; nothing is written for a failing skill.
"""
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = ROOT / "skills"
DIST_DIR = ROOT / "dist"
NAME_MAX = 64
DESCRIPTION_MAX = 200
SKIP_NAMES = {".DS_Store", "__pycache__", ".git"}


def read_frontmatter(skill_md: Path) -> dict[str, str]:
    lines = skill_md.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValueError("SKILL.md must start with a '---' frontmatter block")
    fields: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return fields
        key, sep, value = line.partition(":")
        if sep and not line.startswith((" ", "\t")):
            fields[key.strip()] = value.strip().strip('"').strip("'")
    raise ValueError("frontmatter block is not closed with '---'")


def validate(skill_dir: Path) -> list[str]:
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.is_file():
        return ["missing SKILL.md"]
    try:
        fm = read_frontmatter(skill_md)
    except ValueError as e:
        return [str(e)]
    errors = []
    name, description = fm.get("name", ""), fm.get("description", "")
    if not name:
        errors.append("frontmatter has no `name`")
    elif name != skill_dir.name:
        errors.append(f"`name` is {name!r} but the folder is {skill_dir.name!r}; they must match")
    if len(name) > NAME_MAX:
        errors.append(f"`name` is {len(name)} characters (max {NAME_MAX})")
    if not description:
        errors.append("frontmatter has no `description`")
    elif len(description) > DESCRIPTION_MAX:
        errors.append(f"`description` is {len(description)} characters (max {DESCRIPTION_MAX})")
    return errors


def package(skill_dir: Path) -> Path:
    DIST_DIR.mkdir(exist_ok=True)
    out = DIST_DIR / f"{skill_dir.name}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(skill_dir.rglob("*")):
            rel = path.relative_to(skill_dir)
            if path.is_dir() or SKIP_NAMES.intersection(rel.parts):
                continue
            zf.write(path, Path(skill_dir.name) / rel)
    return out


def main(argv: list[str]) -> int:
    if argv:
        dirs = [SKILLS_DIR / n for n in argv]
        missing = [d.name for d in dirs if not d.is_dir()]
        if missing:
            print(f"no such skill: {', '.join(missing)}", file=sys.stderr)
            return 1
    else:
        dirs = sorted(d for d in SKILLS_DIR.iterdir() if d.is_dir())

    failed = False
    for d in dirs:
        errors = validate(d)
        if errors:
            failed = True
            for e in errors:
                print(f"FAIL {d.name}: {e}", file=sys.stderr)
            continue
        print(f"ok   {d.name} -> {package(d).relative_to(ROOT)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
