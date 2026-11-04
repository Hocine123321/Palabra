import CoreGraphics
import Foundation

/// One thing the tour does and what should be true afterwards.
struct TourStep {
    var id: String
    var caption: String
    /// What the log says was expected.
    var expectation: String
    /// Scene seconds to wait for `check` to pass after `run` returns.
    var timeout: Double = 3
    var run: @MainActor (TourContext) async -> Void
    /// Nil when the scene is as expected, otherwise why not.
    var check: @MainActor (TourContext) -> String?
}

/// The scripted walk through the Books feature, in the order a person would use it (spec "Pull a test").
/// A mutable value shared between a step's `run` and `check`.
final class TourBox<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

@MainActor
enum TourScript {
    /// The values the tour changes and restores.
    struct Originals {
        var dark: Bool
        var level: RecallLevel
        var textSize: ReaderTextSize
        var quality: SceneQuality
    }

    static func steps(originals: Originals) -> [TourStep] {
        var list: [TourStep] = []
        func add(_ id: String, _ caption: String, expect: String, timeout: Double = 3,
                 run: @escaping @MainActor (TourContext) async -> Void, check: @escaping @MainActor (TourContext) -> String?) {
            list.append(TourStep(id: id, caption: caption, expectation: expect, timeout: timeout, run: run, check: check))
        }
        func reading(_ ctx: TourContext) -> String? { ctx.state.mode == .reading ? nil : "not reading (mode \(ctx.state.mode.rawValue))" }
        func page(_ ctx: TourContext, _ n: Int) -> String? {
            if let r = reading(ctx) { return r }
            return ctx.state.page == n ? nil : "page \(ctx.state.page), expected \(n)"
        }
        func firstPage(_ ctx: TourContext) -> String? { ctx.controller.current?.pages.first?.baseID }

        // 1. The desk, left alone; light and dark.
        add("desk-idle", "The desk, left alone", expect: "menu with books", run: { await $0.wait(2.0) },
            check: { $0.state.mode == .menu && !$0.state.books.isEmpty ? nil : "menu not shown" })
        add("appearance-dark", "Dark appearance", expect: "dark lighting", run: { ctx in ctx.send(.setAppearance(dark: true)); await ctx.wait(1.5) },
            check: { $0.controller.isDark ? nil : "still light" })
        add("appearance-light", "Light appearance", expect: "light lighting", run: { ctx in ctx.send(.setAppearance(dark: originals.dark)); await ctx.wait(1.5) },
            check: { $0.controller.isDark == originals.dark ? nil : "appearance not restored" })

        // 2. An empty book, then the real one.
        add("empty-book", "Tap a book without lessons", expect: "stays on the desk", run: { ctx in
            if let empty = ctx.controller.entries.first(where: { $0.isEmpty }), let p = ctx.controller.screenPoint(ofBook: empty.book.id) {
                await ctx.tap(p)
            }
            await ctx.wait(1.0)
        }, check: { $0.state.mode == .menu ? nil : "left the menu" })
        add("open-book", "Tap History: the book opens", expect: "reading", timeout: 8, run: { ctx in
            if let book = ctx.controller.entries.first(where: { !$0.isEmpty }), let p = ctx.controller.screenPoint(ofBook: book.book.id) {
                await ctx.tap(p)
            }
            _ = await ctx.waitUntil(timeout: 8) { ctx.state.mode == .reading }
        }, check: { reading($0) })
        add("first-page", "Go to the first page", expect: "page 1", timeout: 4, run: { ctx in
            if let id = firstPage(ctx) { ctx.send(.goTo(pageID: id)) }
            await ctx.wait(2.5)
        }, check: { page($0, 1) })
        add("dwell", "Read the first page", expect: "page 1 stays", run: { await $0.wait(1.8) }, check: { page($0, 1) })

        // 3. Turning pages.
        add("next-pages", "Next, next, next", expect: "page 4", timeout: 4, run: { ctx in
            for _ in 0..<3 { ctx.send(.next); await ctx.wait(1.2) }
        }, check: { page($0, 4) })
        add("previous-page", "Previous", expect: "page 3", timeout: 4, run: { ctx in ctx.send(.previous); await ctx.wait(1.2) }, check: { page($0, 3) })
        add("jump-far", "Jump far ahead", expect: "page 15", timeout: 5, run: { ctx in
            guard let entry = ctx.controller.current else { return }
            let i = min(entry.pages.count - 1, 14)
            ctx.send(.goTo(pageID: entry.pages[i].baseID))
            await ctx.wait(2.2)
        }, check: { ctx in
            guard let entry = ctx.controller.current else { return "no book" }
            return page(ctx, min(entry.pages.count, 15))
        })
        add("jump-back", "Jump back to the start", expect: "page 1", timeout: 5, run: { ctx in
            if let id = firstPage(ctx) { ctx.send(.goTo(pageID: id)) }
            await ctx.wait(2.2)
        }, check: { page($0, 1) })

        // 4. By hand.
        add("edge-drag", "Drag the page edge past the middle", expect: "page 2", timeout: 4, run: { ctx in
            let c = ctx.controller
            guard let a = c.screenPoint(pageIndex: 0, px: 1150, py: 900), let b = c.screenPoint(pageIndex: 0, px: -250, py: 900) else { return }
            await ctx.swipe(from: a, to: CGPoint(x: max(2, b.x), y: b.y), seconds: 0.7)
            await ctx.wait(1.2)
        }, check: { page($0, 2) })
        add("edge-drag-early", "Drag a little and let go", expect: "page stays 2", timeout: 3, run: { ctx in
            let c = ctx.controller
            guard let a = c.screenPoint(pageIndex: 2, px: 1150, py: 900), let b = c.screenPoint(pageIndex: 2, px: 800, py: 900) else { return }
            await ctx.swipe(from: a, to: b, seconds: 0.8)
            await ctx.wait(1.2)
        }, check: { page($0, 2) })
        add("flick", "Flick the page quickly", expect: "page 4", timeout: 4, run: { ctx in
            let c = ctx.controller
            guard let a = c.screenPoint(pageIndex: 2, px: 1150, py: 900), let b = c.screenPoint(pageIndex: 2, px: 700, py: 900) else { return }
            await ctx.swipe(from: a, to: b, seconds: 0.12)
            await ctx.wait(1.4)
        }, check: { page($0, 4) })
        add("swipe-body", "Swipe the page body", expect: "page 6", timeout: 4, run: { ctx in
            let c = ctx.controller
            guard let a = c.screenPoint(pageIndex: 4, px: 450, py: 900), let b = c.screenPoint(pageIndex: 4, px: -300, py: 900) else { return }
            await ctx.swipe(from: a, to: CGPoint(x: max(2, b.x), y: b.y), seconds: 0.5)
            await ctx.wait(1.4)
        }, check: { page($0, 6) })

        // 5. Terms and Memorize.
        add("term-open", "Tap a highlighted term", expect: "definition opens (or none on these pages)", timeout: 3, run: { ctx in
            if let p = ctx.firstTarget(term: true) { await ctx.tap(p) }
            await ctx.wait(1.0)
        }, check: { ctx in
            if ctx.firstTarget(term: true) == nil && ctx.controller.activeTermID == nil { return nil }
            return ctx.controller.activeTermID != nil ? nil : "term tap did not open a definition"
        })
        add("term-close", "Close the definition", expect: "no definition", run: { ctx in ctx.send(.closeTerm); await ctx.wait(0.6) },
            check: { $0.controller.activeTermID == nil ? nil : "definition still open" })
        add("memorize-on", "Memorize on", expect: "recall on", run: { ctx in ctx.send(.setRecall(true)); await ctx.wait(1.5) },
            check: { $0.state.recall ? nil : "recall off" })
        add("memorize-level-2", "Level: key facts", expect: "level 2", run: { ctx in ctx.send(.setLevel(.keyFacts)); await ctx.wait(1.5) },
            check: { $0.state.level == .keyFacts ? nil : "level \($0.state.level.rawValue)" })
        add("memorize-level-3", "Level: intensive", expect: "level 3", run: { ctx in ctx.send(.setLevel(.intensive)); await ctx.wait(1.5) },
            check: { $0.state.level == .intensive ? nil : "level \($0.state.level.rawValue)" })
        add("memorize-blot", "Tap a hidden answer", expect: "one answer revealed (or none on these pages)", run: { ctx in
            if let p = ctx.firstTarget(term: false) { await ctx.tap(p) }
            await ctx.wait(1.2)
        }, check: { ctx in
            if ctx.firstTarget(term: false) == nil { return nil }
            return ctx.controller.recall.overrides.isEmpty && !ctx.state.revealed ? "blot tap changed nothing" : nil
        })
        add("memorize-reveal", "Reveal the whole page", expect: "revealed", run: { ctx in
            if !ctx.state.revealed { ctx.send(.togglePageReveal) }
            await ctx.wait(1.5)
        }, check: { $0.state.revealed ? nil : "page not revealed" })
        add("memorize-hide", "Hide the answers again", expect: "hidden", run: { ctx in
            if ctx.state.revealed { ctx.send(.togglePageReveal) }
            await ctx.wait(1.5)
        }, check: { !$0.state.revealed ? nil : "page still revealed" })
        add("memorize-off", "Memorize off", expect: "recall off, level restored", run: { ctx in
            ctx.send(.setRecall(false))
            ctx.send(.setLevel(originals.level))
            await ctx.wait(1.5)
        }, check: { !$0.state.recall && $0.state.level == originals.level ? nil : "recall or level not restored" })

        // 6. Tools.
        add("lens-in-hand", "Pick up the magnifying glass", expect: "lens in hand", timeout: 4, run: { ctx in ctx.send(.setTool("lens")); await ctx.wait(1.3) },
            check: { $0.state.tool == "lens" ? nil : "tool \($0.state.tool ?? "none")" })
        let lensStart = TourBox<Double>(0)
        add("lens-across", "Drag the glass across the spine", expect: "glass over the other page", timeout: 3, run: { ctx in
            let c = ctx.controller
            lensStart.value = c.lensPos.x
            let y = c.current?.node.surfaceY(side: 1) ?? 0
            // The finger starts on the glass and ends where the glass should be (the lens rides above the finger).
            guard let a = c.camera.screenPoint(for: SIMD3(c.lensPos.x, y + 0.26, c.lensPos.z)),
                  let b = c.camera.screenPoint(for: SIMD3(-c.lensPos.x, y, c.lensPos.z + 0.38)) else { return }
            await ctx.swipe(from: a, to: CGPoint(x: max(2, min(ctx.controller.camera.size.width - 2, b.x)), y: b.y), seconds: 1.4)
            await ctx.wait(0.6)
        }, check: { $0.controller.lensPos.x * lensStart.value < 0 ? nil : "glass stayed on its page (x \($0.controller.lensPos.x))" })
        add("lens-away", "Put the glass away", expect: "no tool", run: { ctx in ctx.send(.setTool("lens")); await ctx.wait(1.2) },
            check: { $0.state.tool == nil ? nil : "tool still in hand" })
        add("ruler", "Take the ruler and slide it down", expect: "ruler in hand", timeout: 4, run: { ctx in
            ctx.send(.setTool("ruler"))
            await ctx.wait(1.3)
            let c = ctx.controller
            let y = c.current?.node.surfaceY(side: 1) ?? 0
            if let a = c.camera.screenPoint(for: SIMD3(0.5, y, c.rulerZ)), let b = c.camera.screenPoint(for: SIMD3(0.5, y, 0.5)) {
                await ctx.swipe(from: a, to: b, seconds: 1.0)
            }
        }, check: { $0.state.tool == "ruler" ? nil : "tool \($0.state.tool ?? "none")" })
        add("ruler-away", "Put the ruler away", expect: "no tool", run: { ctx in ctx.send(.setTool("ruler")); await ctx.wait(1.2) },
            check: { $0.state.tool == nil ? nil : "tool still in hand" })
        add("bookmark-place", "Place the bookmark", expect: "bookmark on this page", timeout: 4, run: { ctx in ctx.send(.setTool("bookmark")); await ctx.wait(1.3) },
            check: { $0.state.bookmarkPageID != nil && $0.state.bookmarkPageID == $0.state.basePageID ? nil : "bookmark not on this page" })
        add("bookmark-away-and-back", "Turn away and come back", expect: "page 6 again", timeout: 5, run: { ctx in
            ctx.send(.next)
            await ctx.wait(1.4)
            ctx.send(.previous)
            await ctx.wait(1.4)
        }, check: { page($0, 6) })
        add("bookmark-remove", "Take the bookmark away", expect: "no tool", run: { ctx in ctx.send(.setTool("bookmark")); await ctx.wait(1.2) },
            check: { $0.state.tool == nil ? nil : "tool still in hand" })

        // 7. Focus and text size.
        add("focus-with-tool", "Focus Mode with a tool in hand", expect: "focus on", timeout: 4, run: { ctx in
            ctx.send(.setTool("ruler"))
            await ctx.wait(1.0)
            ctx.send(.setFocus(true))
            await ctx.wait(1.6)
        }, check: { $0.state.focus ? nil : "focus off" })
        add("focus-exit", "Leave Focus Mode", expect: "focus off", timeout: 4, run: { ctx in
            ctx.send(.setFocus(false))
            await ctx.wait(1.6)
            ctx.send(.setTool("ruler"))
            await ctx.wait(1.2)
        }, check: { !$0.state.focus && $0.state.tool == nil ? nil : "focus or tool not reset" })
        for size in ReaderTextSize.allCases {
            add("text-size-\(size.rawValue)", "Text size \(size.rawValue)", expect: "text size \(size.rawValue)", timeout: 10, run: { ctx in
                ctx.send(.setTextSize(size))
                _ = await ctx.waitUntil(timeout: 10) { ctx.state.textSize == size && ctx.state.mode == .reading }
                await ctx.wait(1.5)
            }, check: { ctx in ctx.state.textSize == size && ctx.state.mode == .reading ? nil : "text size \(ctx.state.textSize.rawValue)" })
        }
        add("text-size-restore", "Text size back", expect: "original size", timeout: 10, run: { ctx in
            ctx.send(.setTextSize(originals.textSize))
            _ = await ctx.waitUntil(timeout: 10) { ctx.state.textSize == originals.textSize }
            await ctx.wait(1.5)
        }, check: { $0.state.textSize == originals.textSize ? nil : "size not restored" })

        // 8. Free view.
        add("pinch-out", "Pinch out", expect: "zoom below 1", run: { ctx in await ctx.pinch(by: 0.6, seconds: 1.0); await ctx.wait(0.6) },
            check: { $0.controller.free.zoom < 0.95 ? nil : "zoom \($0.controller.free.zoom)" })
        add("pinch-in", "Pinch in", expect: "zoom above 1", run: { ctx in await ctx.pinch(by: 3.2, seconds: 1.2); await ctx.wait(0.6) },
            check: { $0.controller.free.zoom > 1.5 ? nil : "zoom \($0.controller.free.zoom)" })
        add("two-finger-pan", "Two-finger drag", expect: "view moved", run: { ctx in
            await ctx.twoFingerPan(by: CGSize(width: -60, height: 80), seconds: 0.8)
        }, check: { $0.state.viewMoved ? nil : "view not moved" })
        let panPage = TourBox<Int>(0)
        add("one-finger-pan", "One-finger drag while zoomed", expect: "page unchanged", timeout: 3, run: { ctx in
            panPage.value = ctx.state.page
            let c = ctx.viewCentre
            await ctx.swipe(from: c, to: CGPoint(x: c.x + 30, y: c.y - 120), seconds: 0.6)
            await ctx.wait(0.6)
        }, check: { page($0, panPage.value) })
        add("double-tap-reset", "Double tap to reset the view", expect: "zoom 1, not moved", timeout: 3, run: { ctx in
            ctx.controller.doubleTapped(at: ctx.viewCentre)
            await ctx.wait(1.2)
        }, check: { !$0.state.viewMoved && abs($0.controller.camera.zoom - 1) < 0.02 ? nil : "view still moved" })

        // 9. Quality, then back to the desk.
        add("quality-saver", "Battery saver", expect: "saver", run: { ctx in ctx.send(.setQuality(.saver)); await ctx.wait(1.5) },
            check: { $0.controller.quality == .saver ? nil : "quality not saver" })
        add("quality-restore", "Quality back", expect: "original quality", run: { ctx in ctx.send(.setQuality(originals.quality)); await ctx.wait(1.5) },
            check: { $0.controller.quality == originals.quality ? nil : "quality not restored" })
        add("close-book", "Back to the desk", expect: "menu", timeout: 8, run: { ctx in
            ctx.send(.closeBook)
            _ = await ctx.waitUntil(timeout: 8) { ctx.state.mode == .menu }
            await ctx.wait(1.0)
        }, check: { $0.state.mode == .menu ? nil : "mode \($0.state.mode.rawValue)" })
        return list
    }
}
