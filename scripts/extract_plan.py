#!/usr/bin/env python3
"""Materialise the code blocks of the implementation plan.

Blocks are fenced with an info string ending in `file=<repo-relative-path>`.

  extract_plan.py --task N [--root DIR]   write the files of Task N
  extract_plan.py --all    [--root DIR]   write every block in plan order (later tasks overwrite earlier)
  extract_plan.py --check                 parse only; exit 1 on problems
  extract_plan.py --lint                  delimiter-balance check of every .swift block
  extract_plan.py --symbols               report duplicate non-private top-level Swift types (final state)
"""
import argparse
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
PLAN = pathlib.Path(os.environ.get("PLAN_PATH", HERE.parent / "docs/superpowers/plans/2026-09-24-palabra-implementation.md"))
TASK_RE = re.compile(r"^### Task (\d+):")
OPEN_RE = re.compile(r"^```[A-Za-z0-9_+-]*\s+file=(\S+)\s*$")
TYPE_RE = re.compile(r"^(?P<mods>(?:(?:final|public|internal|private|fileprivate|indirect)\s+)*)(?:struct|class|enum|protocol|actor)\s+(?P<name>\w+)")


def blocks():
    task, path, buf = 0, None, []
    for line in PLAN.read_text(encoding="utf-8").splitlines():
        if path is None:
            m = TASK_RE.match(line)
            if m:
                task = int(m.group(1))
                continue
            m = OPEN_RE.match(line)
            if m:
                path, buf = m.group(1), []
        elif line == "```":
            yield task, path, "\n".join(buf) + "\n"
            path = None
        else:
            buf.append(line)
    if path is not None:
        sys.exit(f"error: unterminated block for {path}")


def lint_swift(src):
    """Return delimiter problems: mismatched/unclosed brackets and unterminated strings."""
    errs, n = [], len(src)
    closers = {")": "(", "]": "[", "}": "{"}

    def line(i):
        return src.count("\n", 0, i) + 1

    def string(i, triple):
        while i < n:
            c = src[i]
            if c == "\\":
                i = code(i + 2, ")") if src.startswith("(", i + 1) else i + 2
                continue
            if triple and src.startswith('"""', i):
                return i + 3
            if not triple and c == '"':
                return i + 1
            if not triple and c == "\n":
                errs.append(f"line {line(i)}: unterminated string")
                return i
            i += 1
        errs.append("unterminated string at end of file")
        return i

    def code(i, stop=None):
        stack = []
        while i < n:
            c = src[i]
            if src.startswith("//", i):
                j = src.find("\n", i)
                i = n if j < 0 else j
                continue
            if src.startswith("/*", i):
                j = src.find("*/", i + 2)
                i = n if j < 0 else j + 2
                continue
            if src.startswith('"""', i):
                i = string(i + 3, True)
                continue
            if c == '"':
                i = string(i + 1, False)
                continue
            if c in "([{":
                stack.append((c, i))
            elif c in ")]}":
                if not stack:
                    if stop == c:
                        return i + 1
                    errs.append(f"line {line(i)}: unexpected '{c}'")
                elif stack[-1][0] != closers[c]:
                    errs.append(f"line {line(i)}: '{c}' closes '{stack[-1][0]}' from line {line(stack[-1][1])}")
                    stack.pop()
                else:
                    stack.pop()
            i += 1
        for o, pos in stack:
            errs.append(f"line {line(pos)}: '{o}' never closed")
        return i

    code(0)
    return errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", type=int, help="materialise one task's blocks")
    ap.add_argument("--all", action="store_true", help="materialise every block, in plan order")
    ap.add_argument("--check", action="store_true", help="parse only")
    ap.add_argument("--lint", action="store_true", help="delimiter-balance check of every .swift block")
    ap.add_argument("--symbols", action="store_true", help="report duplicate top-level Swift types")
    ap.add_argument("--root", default=str(HERE.parent))
    a = ap.parse_args()

    if a.task is not None and a.all:
        sys.exit("error: --task and --all are mutually exclusive")
    materialize = a.all or a.task is not None
    verify = a.check or a.lint or a.symbols
    if not materialize and not verify:
        sys.exit("error: pass --task N, --all, or one of --check/--lint/--symbols (combinable)")

    items = list(blocks())
    problems, seen = 0, set()
    for t, p, _ in items:
        if (t, p) in seen:
            print(f"error: Task {t} redefines {p}")
            problems += 1
        seen.add((t, p))

    if verify:
        final = {}
        for _, p, body in items:
            final[p] = body  # later tasks overwrite earlier, last write wins
        if a.lint:
            for p, body in final.items():
                if p.endswith(".swift"):
                    for e in lint_swift(body):
                        print(f"{p}: {e}")
                        problems += 1
        if a.symbols:
            owners = {}
            for p, body in final.items():
                if not p.endswith(".swift"):
                    continue
                for ln in body.splitlines():
                    m = TYPE_RE.match(ln)
                    if m and "private" not in m.group("mods"):
                        owners.setdefault(m.group("name"), set()).add(p)
            for name, files in sorted(owners.items()):
                if len(files) > 1:
                    print(f"duplicate type {name}: {sorted(files)}")
                    problems += 1
        print(f"{len(items)} blocks, {len(final)} files, {problems} problems")
        if problems:
            sys.exit(1)
        if not materialize:
            return

    wanted = items if a.all else [i for i in items if i[0] == a.task]
    if a.task is not None and not wanted:
        sys.exit(f"error: no blocks for task {a.task}")
    root = pathlib.Path(a.root)
    for _, p, body in wanted:
        dest = root / p
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(body, encoding="utf-8")
        print(f"wrote {p}")


if __name__ == "__main__":
    main()
