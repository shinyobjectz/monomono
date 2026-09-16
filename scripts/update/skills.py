#!/usr/bin/env python3
"""Generate .agents/skills from PROJECT.md, feature.md, Gherkin, and library.md.

Generated folders carry a `.generated` marker and are rewritten on every sync.
Folders without the marker are hand-authored and left alone.
Domain-free: it reads front matter and Gherkin, nothing else.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

GENERATED = ".generated"
MAX_LINES = 200
FEATURE_TITLE = re.compile(r"^\s*Feature:\s*(.+)$")
SCENARIO_TITLE = re.compile(r"^\s*Scenario(?: Outline)?:\s*(.+)$")
STEP_LINE = re.compile(r"^\s*(Given|When|Then|And|But)\s+(.+)$")


@dataclass
class Doc:
    path: Path
    meta: dict = field(default_factory=dict)
    body: str = ""
    lines: int = 0


def parse_front_matter(path: Path) -> Doc:
    text = path.read_text(encoding="utf-8")
    doc = Doc(path=path, lines=text.count("\n") + 1)
    if not text.startswith("---"):
        doc.body = text
        return doc
    parts = text.split("\n---", 1)
    head = parts[0][3:]
    doc.body = parts[1].lstrip("\n") if len(parts) > 1 else ""
    key = None
    for raw in head.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if m and not line.startswith(" "):
            key, value = m.group(1), m.group(2).strip()
            if value in ("", "[]"):
                doc.meta[key] = [] if value == "[]" else ""
            else:
                doc.meta[key] = value.strip("\"'")
        elif key is not None and line.strip().startswith("- "):
            if not isinstance(doc.meta.get(key), list):
                doc.meta[key] = []
            doc.meta[key].append(line.strip()[2:].strip().strip("\"'"))
    return doc


def scenarios(feature_dir: Path) -> list[tuple[str, str, list[str]]]:
    out = []
    for f in sorted((feature_dir / "bdd").glob("*.feature")):
        title = ""
        for line in f.read_text(encoding="utf-8").splitlines():
            if m := FEATURE_TITLE.match(line):
                title = m.group(1).strip()
            elif m := SCENARIO_TITLE.match(line):
                out.append((title, m.group(1).strip(), []))
            elif (m := STEP_LINE.match(line)) and out:
                out[-1][2].append(f"{m.group(1)} {m.group(2).strip()}")
    return out


def write_generated(dest: Path, content: str) -> None:
    if dest.exists() and not (dest / GENERATED).exists():
        print(f"skip hand-authored {dest}", file=sys.stderr)
        return
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    (dest / GENERATED).write_text("written by just agents sync; do not edit\n")
    (dest / "SKILL.md").write_text(content, encoding="utf-8")


def bullet(items) -> str:
    if isinstance(items, str):
        items = [items] if items else []
    return "".join(f"- {i}\n" for i in items)


def feature_skill(project: str, slug: str, doc: Doc, feature_dir: Path, root: Path) -> str:
    meta = doc.meta
    name = f"{project}-{slug}"
    desc = meta.get("description") or f"Use when working on the {slug} feature of {project}."
    parts = [f"---\nname: {name}\ndescription: {desc}\n---\n\n# {meta.get('title', slug)}\n\n"]
    parts.append(f"Spec: `{feature_dir.relative_to(root)}/bdd`. Status: {meta.get('status', 'spec')}.\n\n")
    if meta.get("summary"):
        parts.append(meta["summary"] + "\n\n")
    if meta.get("do"):
        parts.append("## Do\n\n" + bullet(meta["do"]) + "\n")
    if meta.get("dont"):
        parts.append("## Don't\n\n" + bullet(meta["dont"]) + "\n")
    if meta.get("implements"):
        parts.append("## Implements\n\n" + bullet(meta["implements"]) + "\n")
    scen = scenarios(feature_dir)
    if scen:
        parts.append("## Scenarios\n\n")
        for feat, title, steps in scen:
            parts.append(f"### {title}\n\n")
            parts.append("".join(f"- {s}\n" for s in steps) + "\n")
    tests = sorted(p.name for p in (feature_dir / "test").glob("*") if p.name != ".gitkeep" and p.is_file())
    if tests:
        parts.append("## Tests\n\n" + bullet(tests) + "\n")
    body = doc.body.strip()
    if body:
        parts.append("## Context\n\n" + body + "\n")
    return "".join(parts)


def library_skill(domain: str, doc: Doc, lib_dir: Path, root: Path) -> str:
    meta = doc.meta
    desc = meta.get("description") or f"Use when changing library/{domain}."
    parts = [f"---\nname: library-{domain}\ndescription: {desc}\n---\n\n# {meta.get('title', domain)}\n\n"]
    parts.append(f"Source: `{lib_dir.relative_to(root)}`.\n\n")
    if meta.get("summary"):
        parts.append(meta["summary"] + "\n\n")
    if meta.get("do"):
        parts.append("## Do\n\n" + bullet(meta["do"]) + "\n")
    if meta.get("dont"):
        parts.append("## Don't\n\n" + bullet(meta["dont"]) + "\n")
    bucks = sorted(str(p.relative_to(lib_dir)) for p in lib_dir.rglob("BUCK"))
    if bucks:
        parts.append("## Targets\n\n" + bullet(bucks) + "\n")
    body = doc.body.strip()
    if body:
        parts.append("## Context\n\n" + body + "\n")
    return "".join(parts)


def check(root: Path) -> int:
    errors = 0
    docs = list((root / "context" / "projects").glob("*/PROJECT.md"))
    docs += list((root / "context" / "projects").glob("*/features/*/feature.md"))
    docs += list((root / "library").glob("*/library.md"))
    for path in docs:
        doc = parse_front_matter(path)
        rel = path.relative_to(root)
        if doc.lines > MAX_LINES:
            print(f"{rel}: {doc.lines} lines (max {MAX_LINES})", file=sys.stderr)
            errors += 1
        for key in ("name", "description"):
            if not doc.meta.get(key):
                print(f"{rel}: front matter needs {key}", file=sys.stderr)
                errors += 1
    for fdir in (root / "context" / "projects").glob("*/features/*"):
        if not fdir.is_dir() or fdir.name.startswith("."):
            continue
        feats = list((fdir / "bdd").glob("*.feature"))
        if not feats:
            print(f"{fdir.relative_to(root)}/bdd: no .feature files", file=sys.stderr)
            errors += 1
        for f in feats:
            text = f.read_text(encoding="utf-8")
            if not re.search(r"^\s*Feature:", text, re.M):
                print(f"{f.relative_to(root)}: missing Feature:", file=sys.stderr)
                errors += 1
            if not re.search(r"^\s*Scenario( Outline)?:", text, re.M):
                print(f"{f.relative_to(root)}: missing Scenario:", file=sys.stderr)
                errors += 1
    return errors


def generate(root: Path) -> None:
    skills = root / ".agents" / "skills"
    skills.mkdir(parents=True, exist_ok=True)
    tree: list[str] = []
    wanted: set[Path] = set()

    projects = root / "context" / "projects"
    for pdir in sorted(projects.glob("*")) if projects.exists() else []:
        if not (pdir / "PROJECT.md").exists():
            continue
        project = pdir.name
        for fdir in sorted((pdir / "features").glob("*")):
            fm = fdir / "feature.md"
            if not fm.exists():
                continue
            doc = parse_front_matter(fm)
            dest = skills / "features" / project / fdir.name
            write_generated(dest, feature_skill(project, fdir.name, doc, fdir, root))
            wanted.add(dest)
            tree.append(f"features/{project}/{fdir.name}")

    library = root / "library"
    for ldir in sorted(library.glob("*")) if library.exists() else []:
        lm = ldir / "library.md"
        if not lm.exists():
            continue
        doc = parse_front_matter(lm)
        dest = skills / "library" / ldir.name
        write_generated(dest, library_skill(ldir.name, doc, ldir, root))
        wanted.add(dest)
        tree.append(f"library/{ldir.name}")

    # prune stale generated folders
    for marker in skills.rglob(GENERATED):
        d = marker.parent
        if d not in wanted:
            shutil.rmtree(d)
    for group in ("features", "library"):
        gdir = skills / group
        if gdir.exists():
            for sub in sorted(gdir.rglob("*"), reverse=True):
                if sub.is_dir() and not any(sub.iterdir()):
                    sub.rmdir()
            if gdir.exists() and not any(gdir.iterdir()):
                gdir.rmdir()

    hand = sorted(
        p.parent.name for p in skills.glob("*/SKILL.md") if not (p.parent / GENERATED).exists()
    )
    index = ["# Skills\n\n"]
    index.append(
        "Generated by `just agents sync` from `PROJECT.md`, `feature.md`, Gherkin, and `library.md`. "
        "A `.generated` marker means the folder is rewritten on sync; edit the source instead. "
        "Folders without the marker are hand-authored procedures and are left alone.\n\n"
    )
    index.append("| Working on | Open |\n| --- | --- |\n")
    index.append("| a project feature | `features/<project>/<slug>` |\n")
    index.append("| a library domain | `library/<domain>` |\n")
    index.append("| a working procedure | the hand-authored skill folder |\n\n")
    if hand:
        index.append("## Procedures\n\n" + "".join(f"- `{h}/`\n" for h in hand) + "\n")
    if tree:
        index.append("## Generated\n\n" + "".join(f"- `{t}/`\n" for t in tree) + "\n")
    (skills / "AGENTS.md").write_text("".join(index), encoding="utf-8")
    print(f"skills: {len(tree)} generated, {len(hand)} hand-authored")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    if args.check:
        n = check(root)
        print("skills check ok" if n == 0 else f"skills check: {n} problem(s)", file=sys.stderr)
        return 1 if n else 0
    generate(root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
