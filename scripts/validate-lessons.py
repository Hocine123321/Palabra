#!/usr/bin/env python3
"""Checks the bundled textbook lessons with the same rules as LessonValidator.swift (see docs/features/books.md).

Run from the repo root:  python3 scripts/validate-lessons.py
Exits non-zero and prints every problem. CI runs it before building, so a bad lesson never reaches a device.
"""
import json
import os
import sys

BOOKS_DIR = os.path.join("Palabra", "Resources", "Books")
RULES = [("{{", "}}"), ("[[", "]]"), ("**", "**")]
LEVELS = {"e", "k", "i"}
KNOWN_BLOCKS = {
    "heading", "paragraph", "list", "keyPoint", "quote", "timeline", "stats",
    "comparison", "causeEffect", "process", "definitions", "image",
}


def scan(source):
    """Returns (term ids used, problems). Mirrors InlineMarkup.scan."""
    terms, problems = [], []
    i = 0
    while i < len(source):
        matched = False
        for open_, close in RULES:
            if not source.startswith(open_, i):
                continue
            start = i + len(open_)
            end = source.find(close, start)
            if end < 0:
                problems.append('unclosed "%s"' % open_)
                continue
            inner = source[start:end]
            if open_ == "{{":
                bar = inner.rfind("|")
                text, ident = (inner[:bar], inner[bar + 1:].strip()) if bar >= 0 else ("", "")
                if bar < 0:
                    problems.append("term without an id: " + inner)
                elif not text or not ident:
                    problems.append("term with an empty text or id: " + inner)
                else:
                    terms.append(ident)
                    matched = True
            elif open_ == "[[":
                bar = inner.rfind("|")
                text = inner
                if bar >= 0:
                    tag = inner[bar + 1:].strip()
                    if tag in LEVELS:
                        text = inner[:bar]
                    else:
                        problems.append('unknown recall level "%s" (use e, k or i)' % tag)
                matched = bool(text)
            else:
                matched = bool(inner)
            if matched:
                i = end + len(close)
                break
        if not matched:
            i += 1
    return terms, problems


def block_texts(block):
    t = block.get("type")
    out = []

    def add(value):
        if isinstance(value, str):
            out.append(value)

    if t == "heading" or t == "paragraph":
        add(block.get("text"))
    elif t == "list":
        add(block.get("title")); out += block.get("items", [])
    elif t == "keyPoint":
        add(block.get("label")); add(block.get("text"))
    elif t == "quote":
        add(block.get("text")); add(block.get("source"))
    elif t == "timeline":
        add(block.get("title"))
        for e in block.get("events", []):
            add(e.get("date")); add(e.get("title")); add(e.get("detail"))
    elif t == "stats":
        add(block.get("title"))
        for s in block.get("stats", []):
            for k in ("label", "value", "unit", "note"):
                add(s.get(k))
    elif t == "comparison":
        add(block.get("title")); add(block.get("corner")); out += block.get("columns", [])
        for r in block.get("rows", []):
            add(r.get("label")); out += r.get("cells", [])
    elif t == "causeEffect":
        add(block.get("title"))
        for s in block.get("stages", []):
            add(s.get("label")); out += s.get("nodes", [])
    elif t == "process":
        add(block.get("title"))
        for s in block.get("steps", []):
            add(s.get("title")); add(s.get("detail"))
    elif t == "definitions":
        add(block.get("title"))
        for d in block.get("definitions", []):
            add(d.get("term")); add(d.get("definition"))
    elif t == "image":
        add(block.get("caption"))
    return out


def structure(block):
    t = block.get("type")
    out = []
    if t not in KNOWN_BLOCKS:
        return ['unknown block type "%s"' % t]
    if t == "heading":
        if not block.get("text"): out.append("empty heading")
        if block.get("level", 2) not in (1, 2, 3): out.append("heading level must be 1, 2 or 3")
    elif t == "paragraph" and not block.get("text"):
        out.append("empty paragraph")
    elif t == "list" and not block.get("items"):
        out.append("list has no items")
    elif t == "keyPoint" and not block.get("text"):
        out.append("empty key point")
    elif t == "quote" and not block.get("text"):
        out.append("empty quote")
    elif t == "timeline" and not block.get("events"):
        out.append("timeline has no events")
    elif t == "stats" and not block.get("stats"):
        out.append("stats has no items")
    elif t == "comparison":
        cols, rows = block.get("columns", []), block.get("rows", [])
        if not cols: out.append("comparison has no columns")
        if not rows: out.append("comparison has no rows")
        for r in rows:
            if len(r.get("cells", [])) != len(cols):
                out.append('comparison row "%s" has %d cells for %d columns' % (r.get("label"), len(r.get("cells", [])), len(cols)))
    elif t == "causeEffect":
        stages = block.get("stages", [])
        if len(stages) < 2: out.append("cause-and-effect needs at least two stages")
        if any(not s.get("nodes") for s in stages): out.append("a stage has no nodes")
    elif t == "process" and not block.get("steps"):
        out.append("process has no steps")
    elif t == "definitions" and not block.get("definitions"):
        out.append("definitions has no items")
    elif t == "image":
        if not block.get("image"): out.append("image has no name")
        if not block.get("alt"): out.append('image "%s" has no alt text' % block.get("image"))
    return out


def validate_lesson(lesson, label):
    problems = []
    if not lesson.get("id") or "/" in lesson["id"]:
        problems.append('%s: lesson id must not be empty or contain "/"' % label)
    if not lesson.get("title"): problems.append("%s: lesson has no title" % label)
    pages = lesson.get("pages", [])
    if not pages: problems.append("%s: lesson has no pages" % label)

    glossary = set(lesson.get("terms", {}).keys())
    for page in pages:
        for block in page.get("blocks", []):
            if block.get("type") == "definitions":
                glossary |= {d["id"] for d in block.get("definitions", []) if d.get("id")}

    seen = set()
    for page in pages:
        pid = page.get("id", "")
        at = "%s: page %s" % (label, pid)
        if not pid or "/" in pid: problems.append('%s: page id must not be empty or contain "/"' % at)
        if pid in seen: problems.append("%s: duplicate page id" % at)
        seen.add(pid)
        if not page.get("title"): problems.append("%s: no title" % at)
        if not page.get("blocks"): problems.append("%s: no blocks" % at)
        for n, block in enumerate(page.get("blocks", []), 1):
            where = "%s, block %d" % (at, n)
            problems += ["%s: %s" % (where, p) for p in structure(block)]
            for text in block_texts(block):
                terms, issues = scan(text)
                problems += ["%s: %s" % (where, p) for p in issues]
                problems += ['%s: unknown term id "%s"' % (where, t) for t in terms if t not in glossary]
    return problems


def main():
    problems = []
    catalogue_path = os.path.join(BOOKS_DIR, "textbooks.json")
    try:
        catalogue = json.load(open(catalogue_path, encoding="utf-8"))
    except (OSError, ValueError) as error:
        print("catalogue: %s" % error)
        return 1

    # Resources are flattened into the bundle root, so every JSON file name must be unique across the whole app.
    on_disk = {f for f in os.listdir(BOOKS_DIR) if f.endswith(".json")}
    referenced = set()
    seen_books = set()
    for book in catalogue.get("books", []):
        if book["id"] in seen_books: problems.append("duplicate book id " + book["id"])
        seen_books.add(book["id"])
        seen_lessons = set()
        for chapter in book.get("chapters", []):
            for ref in chapter.get("lessons", []):
                label = "%s/%s" % (book["id"], ref["id"])
                if ref["id"] in seen_lessons or "/" in ref["id"]:
                    problems.append("%s: lesson id is used twice or contains \"/\"" % label)
                seen_lessons.add(ref["id"])
                name = ref["file"] + ".json"
                referenced.add(name)
                path = os.path.join(BOOKS_DIR, name)
                if not os.path.exists(path):
                    problems.append("%s: missing file %s" % (label, name))
                    continue
                try:
                    lesson = json.load(open(path, encoding="utf-8"))
                except ValueError as error:
                    problems.append("%s: not valid JSON (%s)" % (label, error))
                    continue
                if lesson.get("id") != ref["id"]:
                    problems.append('%s: the lesson file says id "%s"' % (label, lesson.get("id")))
                problems += validate_lesson(lesson, label)
    for name in sorted(on_disk - referenced - {"textbooks.json"}):
        problems.append("%s is not registered in textbooks.json" % name)

    if problems:
        print("Lesson validation failed:")
        for p in problems: print("  - " + p)
        return 1
    print("Lessons OK (%d book(s), %d lesson file(s))." % (len(catalogue.get("books", [])), len(referenced)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
