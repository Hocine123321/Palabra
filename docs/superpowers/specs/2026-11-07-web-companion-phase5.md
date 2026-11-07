# Web companion, phase 5 (part 1): Artifacts

Status: built on `experimental`. Chat and Books are **not** part of this step. Builds on [phase 4](2026-11-07-web-companion-phase4.md).

## What the person gets

A third tab, **Artifacts**. It lists the pages you made in Palabra; tapping one opens it on the PC (headings, text, lists, tables,
charts, stats, checklists, roadmaps, sections, columns). Apps (the interactive ones) appear in the list marked **Opens on your
phone**.

## Decision to review: apps do not run on the web yet

An `app` artifact is generated HTML with script and a bridge (`window.palabra`) to the phone. In the app it is confined by a WebKit
content rule plus a CSP, and `ArtifactSandbox` calls those values "the security boundary". A browser page cannot copy that
boundary by itself, and the page that would host the artifact also holds the link key. Running generated script there could read
the person's data or send changes. So apps are listed and never sent: the phone answers `not-found` even if the page asks for one
by id (tested).

To run apps safely later it needs, at least: a sandboxed iframe with no `allow-same-origin`, a CSP on its `srcdoc`, and a
message bridge that only forwards the capabilities that artifact was granted, through the same allow-list as the page. That is
a design of its own and deserves its own review, so it is left out here.

## Messages added (all read-only)

| Type | Payload | Reply |
|---|---|---|
| `artifacts` | none | `ack {result: [{id, title, kind, viewable, runnable, updatedAt}]}`, newest first, at most 200, **never a payload** |
| `artifact` | `{id}` | `ack {result: {id, title, blocks}}` for a page; `reject not-found` for an app, an unknown id or an undecodable page |

**The phone does the work, the page only draws.** `WebArtifactReader` decodes the page and resolves tables and charts with the app's
own `SpecBindLoader`, so there is no second copy of the binding rules in JavaScript. Binds are limited to the reads the web page may
already make (`readAllowList`); a bind to anything else (`storage.get`, a write) shows an inline note and runs nothing (tested).
Checklist and roadmap ticks are sent as they are on the phone.

**The page does not trust the phone's limits.** It re-caps nesting at 4 levels and 60 blocks, escapes every string, draws nothing
for an unknown block type, and survives junk where lists are expected (tested, including an `<img onerror>` in every field).

## Limits

- Read-only: ticking a checklist on the web is not possible yet. It would be a new write (and a new line on the write allow-list), so
  it is a deliberate next step, not an accident.
- Artifacts are fetched live and are **not** saved in the browser, so the tab needs the phone connected. When it is away the tab says
  so. (Offline artifacts would need the cache to hold them; the cache size and what to keep are for you to decide.)
- No version history, restore or delete from the web.
- Nothing in Swift for phase 5 has been compiled or run yet.

## Still to build in phase 5

Chat (most recent conversation, cached) and Books (pages cached on visit).
