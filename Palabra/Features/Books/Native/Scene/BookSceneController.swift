import CoreGraphics
import Foundation
import SceneKit
import UIKit

extension ReaderTextSize {
    /// `TEXT_SCALE` of the web scene: how much the page text is scaled before pagination.
    var pageScale: Double {
        switch self {
        case .smaller: return 0.96
        case .standard: return 1.1
        case .larger: return 1.26
        case .largest: return 1.42
        }
    }
}

/// What the controller starts from (the payload the web scene received as JSON).
struct NativeSceneConfig {
    var library: BookLibrary
    var lastPageID: [String: String] = [:]
    var bookmarks: [String: String] = [:]
    var textSize: ReaderTextSize = .standard
    var recallLevel: RecallLevel = .essential
    var quality: SceneQuality = .standard
    var reducedMotion = false
}

/// A page bitmap with the places on it that react to a tap.
struct PageImage {
    var image: CGImage
    var hits: [HitRegion]
}

private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// The native desk: owns the SceneKit scene and runs everything `app.js` does (menu, opening, page turns, state). It speaks
/// the same `SceneMessage` / `SceneCommand` language as the web scene, so the HUD and `BooksSceneModel` do not change.
@MainActor
final class BookSceneController {
    final class Entry {
        let book: Book
        var pages: [PhysicalPage]
        let node: BookNode
        var menu = (x: 0.0, z: 0.0, ry: 0.0)
        var hover = 0.0
        var isEmpty: Bool { pages.isEmpty }
        init(book: Book, pages: [PhysicalPage], node: BookNode) {
            self.book = book
            self.pages = pages
            self.node = node
        }
    }

    // MARK: Scene

    let scene = SCNScene()
    let camera = CameraRig()
    let desk = DeskNode()
    let lighting = SceneLighting()
    let tweens = Tweens()
    private let booksRoot = SCNNode()

    // MARK: State

    private(set) var state = SceneState()
    private(set) var entries: [Entry] = []
    private(set) var current: Entry?
    /// 0-based index of the page being read.
    private(set) var pageIndex = 0
    private(set) var recall: RecallState
    private(set) var textSize: ReaderTextSize
    private(set) var quality: SceneQuality
    private(set) var isDark = false
    private(set) var insets = (top: 0.0, bottom: 0.0)
    private(set) var panZ = 0.0
    private(set) var panLimit = 0.0
    private(set) var pxPerZ = 1.0
    private(set) var isLoaded = false
    var hoverBook: String?
    var sink: ((SceneMessage) -> Void)?
    /// Called when the view should switch its render quality.
    var onQualityChange: ((SceneQuality) -> Void)?

    private var config: NativeSceneConfig
    private var closeAfterOpen = false
    private var cameraTween: Tween?
    private var propsOpacity = 1.0
    private var leafTweens: [Int: Tween] = [:]
    private var cache: [String: PageImage] = [:]
    private var pending: [String: Int] = [:]
    private var generation = 0
    private var assigned: [String: Set<Int>] = [:]
    private var rebuildToken = 0

    init(config: NativeSceneConfig) {
        self.config = config
        recall = RecallState(level: config.recallLevel)
        textSize = config.textSize
        quality = config.quality
        scene.rootNode.addChildNode(desk.root)
        scene.rootNode.addChildNode(booksRoot)
        scene.rootNode.addChildNode(lighting.root)
        scene.rootNode.addChildNode(camera.node)
        scene.background.contents = SceneLighting.background(dark: false)
        tweens.timeScale = config.reducedMotion ? 0.001 : 1
        state.textSize = textSize
        state.level = recall.level
        lighting.setShadows(quality != .saver)
    }

    var isBusy: Bool { tweens.isActive || !pending.isEmpty }

    var isWide: Bool { metrics.isWide }

    var metrics: ViewMetrics {
        ViewMetrics(size: camera.size, insetTop: insets.top, insetBottom: insets.bottom, fovDegrees: camera.fovDegrees)
    }

    // MARK: Loading

    /// Paginates every book and builds the nodes; posts `.ready` when done.
    func load() async {
        await rebuild()
        isLoaded = true
        menuLayout()
        frameMenu(animated: false)
        state.problems = config.library.problems.count
        emit()
        post(.ready)
    }

    private func post(_ message: SceneMessage) { sink?(message) }

    /// Re-runs pagination for every book (text size changed, or first load).
    private func rebuild() async {
        rebuildToken += 1
        let token = rebuildToken
        for entry in entries { entry.node.root.removeFromParentNode() }
        entries = []
        cache = [:]
        pending = [:]
        assigned = [:]
        generation += 1
        let scale = textSize.pageScale
        let books = config.library.books
        let box = UncheckedBox(books)
        let paged: [[PhysicalPage]] = await Task.detached(priority: .userInitiated) {
            box.value.map { book in
                var pages: [PhysicalPage] = []
                for bp in book.pages {
                    pages += PageLayout.paginate(bp, measure: PageFonts.measure, rtl: book.isRightToLeft, subject: book.subject.rawValue, scale: scale)
                }
                for i in pages.indices { pages[i].number = i + 1 }
                return pages
            }
        }.value
        guard token == rebuildToken else { return }
        for (book, pages) in zip(books, paged) {
            let subject = book.subject.rawValue
            let leafCount = max(1, (pages.count + 1) / 2)
            let style = BookStyle(subject: subject, rtl: book.isRightToLeft, leafCount: leafCount, bulk: BookStyle.bulk(for: subject))
            let node = BookNode(style: style, covers: CoverArt.make(subject: subject), pageEdge: CoverArt.pageEdge())
            booksRoot.addChildNode(node.root)
            entries.append(Entry(book: book, pages: pages, node: node))
        }
    }

    // MARK: Appearance and size

    func setAppearance(dark: Bool) {
        isDark = dark
        desk.setAppearance(dark: dark)
        lighting.setAppearance(dark: dark)
        scene.background.contents = SceneLighting.background(dark: dark)
    }

    func setQuality(_ q: SceneQuality) {
        quality = q
        lighting.setShadows(q != .saver)
        onQualityChange?(q)
    }

    func setSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let wasWide = isWide
        camera.setSize(size)
        camera.setShift(metrics.projectionShift)
        if isLoaded {
            if state.mode == .menu, wasWide != isWide { menuLayout() }
            reframe()
        }
    }

    func setInsets(top: Double, bottom: Double) {
        insets = (max(0, top), max(0, bottom))
        camera.setShift(metrics.projectionShift)
        if isLoaded { reframe() }
    }

    /// Puts the camera where the current mode wants it, without animating.
    private func reframe() {
        switch state.mode {
        case .reading: moveCamera(readTarget(pageIndex), duration: 0)
        case .menu: frameMenu(animated: false)
        default: break
        }
    }

    // MARK: Camera

    func moveCamera(_ target: CameraPose, duration: Double) {
        tweens.cancel(cameraTween)
        let from = camera.pose
        if duration <= 0 {
            camera.setPose(target)
            return
        }
        cameraTween = tweens.add(duration: duration, ease: .inOut) { [weak self] t in
            guard let self else { return }
            let position = from.position + (target.position - from.position) * t
            let look = from.look + (target.look - from.look) * t
            self.camera.setPose(CameraPose(position: position, look: look))
        }
    }

    private func moveCameraDelayed(_ target: CameraPose, delay: Double, duration: Double) {
        tweens.add(duration: 0.0001, delay: delay, onUpdate: { _ in }, onDone: { [weak self] in
            self?.moveCamera(target, duration: duration)
        })
    }

    func frameMenu(animated: Bool) {
        moveCamera(Framing.menu(metrics), duration: animated ? 1.1 : 0)
    }

    private func coverPose(_ entry: Entry) -> CameraPose { Framing.cover(rtl: entry.book.isRightToLeft, metrics) }

    func readTarget(_ index: Int, focus: Bool? = nil) -> CameraPose {
        guard let entry = current else { return camera.pose }
        let onRight = index % 2 == 0
        let frame = Framing.reading(
            page: index, rtl: entry.book.isRightToLeft, focus: focus ?? state.focus,
            surfaceY: entry.node.surfaceY(side: onRight ? 1 : -1), pan: panZ, metrics
        )
        panLimit = frame.panLimit
        pxPerZ = frame.pxPerZ
        panZ = frame.pan
        return frame.pose
    }

    // MARK: Menu

    func menuLayout() {
        let wide = isWide
        for (i, entry) in entries.enumerated() {
            let slot = Framing.menuSlot(index: i, wide: wide)
            entry.menu = (slot.x, slot.z, slot.ry)
            entry.hover = 0
            entry.node.root.position = SCNVector3(Float(slot.x), 0, Float(slot.z))
            entry.node.root.eulerAngles = SCNVector3(0, Float(slot.ry), 0)
            entry.node.root.isHidden = false
            entry.node.setCoverOpen(0)
            for leaf in 0..<entry.node.leafCount { entry.node.setLeafProgress(leaf, 0) }
            entry.node.layout()
            ensureTextures(entry, around: 0, immediate: true)
        }
    }

    private func hoverStep(dt: Double) {
        for entry in entries {
            let target = hoverBook == entry.book.id ? 1.0 : 0.0
            let k = entry.hover + (target - entry.hover) * min(1, dt * 9)
            entry.hover = abs(target - k) < 0.002 ? target : k
            let g = entry.node.root
            g.position = SCNVector3(Float(entry.menu.x), Float(entry.hover * 0.07), Float(entry.menu.z + entry.hover * 0.1))
            g.eulerAngles = SCNVector3(
                Float(-entry.hover * 0.045),
                Float(entry.menu.ry + entry.hover * (entry.menu.ry > 0 ? -0.05 : 0.05)),
                0
            )
        }
    }

    // MARK: Open / close

    func openBook(id: String, pageID: String?) {
        guard state.mode == .menu, isLoaded else { return }
        guard let entry = entries.first(where: { $0.book.id == id }), !entry.isEmpty else {
            post(.empty(bookID: id))
            return
        }
        current = entry
        state.mode = .opening
        state.bookID = id
        let resume: Int
        if let pageID, let i = entry.pages.firstIndex(where: { $0.baseID == pageID }) {
            resume = i
        } else {
            resume = resumeIndex(entry)
        }
        let start = Int(BookMath.clamp(Double(resume), 0, Double(entry.pages.count - 1)))
        pageIndex = start
        state.page = start
        panZ = 0
        state.pageCount = entry.pages.count
        setLeavesInstant(entry, page: start)
        ensureTextures(entry, around: start, immediate: true)
        let wide = isWide
        for other in entries where other !== entry {
            let from = other.node.root.position
            tweens.add(duration: 0.7, ease: .inOut) { t in
                other.node.root.position = SCNVector3(
                    from.x + (wide ? 3.5 : 0), from.y, Float(BookMath.lerp(Double(from.z), Double(from.z) - 3.4, t))
                )
            }
        }
        let root = entry.node.root
        let fromPos = root.position
        let fromRY = Double(root.eulerAngles.y)
        tweens.add(duration: 0.8, ease: .inOut) { t in
            root.position = SCNVector3(
                Float(BookMath.lerp(Double(fromPos.x), 0, t)), Float(sin(t * .pi) * 0.35), Float(BookMath.lerp(Double(fromPos.z), 0, t))
            )
            root.eulerAngles = SCNVector3(0, Float(BookMath.lerp(fromRY, 0, t)), 0)
        }
        moveCamera(coverPose(entry), duration: 0.8)
        tweens.add(duration: 1.15, delay: 0.55, ease: .inOut, onUpdate: { t in entry.node.setCoverOpen(t) }, onDone: { [weak self] in
            guard let self else { return }
            self.state.mode = .reading
            self.afterNavigate()
            if self.closeAfterOpen {
                self.closeAfterOpen = false
                self.closeBook()
            }
        })
        moveCameraDelayed(readTarget(start, focus: false), delay: 0.55, duration: 1.2)
        emit()
    }

    private func resumeIndex(_ entry: Entry) -> Int {
        let last = config.lastPageID[entry.book.id]
        let bookIndex = entry.book.resumeIndex(lastPageID: last)
        guard entry.book.pages.indices.contains(bookIndex) else { return 0 }
        let baseID = entry.book.pages[bookIndex].id
        return entry.pages.firstIndex(where: { $0.baseID == baseID }) ?? 0
    }

    func closeBook() {
        if state.mode == .opening {
            closeAfterOpen = true
            return
        }
        guard state.mode == .reading, let entry = current else { return }
        setFocus(false, silent: true)
        state.mode = .closing
        let turned = (0..<entry.node.leafCount).filter { entry.node.leafProgress($0) > 0.5 }
        for (k, leaf) in turned.enumerated() {
            animateLeaf(entry, leaf, to: 0, duration: 0.45, delay: min(0.5, Double(k) * 0.05))
        }
        let wait = turned.isEmpty ? 0 : min(0.5, Double(turned.count) * 0.05) + 0.45
        tweens.add(duration: 0.9, delay: wait, ease: .inOut, onUpdate: { t in entry.node.setCoverOpen(1 - t) }, onDone: { [weak self] in
            guard let self else { return }
            let closed = self.current
            self.current = nil
            self.state.mode = .menu
            self.state.bookID = nil
            self.state.page = 0
            self.pageIndex = 0
            self.menuTransitionBack(closed)
            self.emit()
        })
        moveCameraDelayed(coverPose(entry), delay: wait, duration: 0.9)
        emit()
    }

    private func menuTransitionBack(_ closed: Entry?) {
        for entry in entries {
            let from = entry.node.root.position
            let fromRY = Double(entry.node.root.eulerAngles.y)
            let lift = entry === closed ? 0.3 : 0.0
            tweens.add(duration: 0.9, ease: .inOut) { t in
                entry.node.root.position = SCNVector3(
                    Float(BookMath.lerp(Double(from.x), entry.menu.x, t)), Float(sin(t * .pi) * lift),
                    Float(BookMath.lerp(Double(from.z), entry.menu.z, t))
                )
                entry.node.root.eulerAngles = SCNVector3(0, Float(BookMath.lerp(fromRY, entry.menu.ry, t)), 0)
            }
        }
        frameMenu(animated: true)
    }

    private func setLeavesInstant(_ entry: Entry, page: Int) {
        let flipped = (page + 1) / 2
        for leaf in 0..<entry.node.leafCount { entry.node.setLeafProgress(leaf, leaf < flipped ? 1 : 0) }
        entry.node.layout()
    }

    // MARK: Navigation

    func next() { goToPage(pageIndex + 1) }
    func previous() { goToPage(pageIndex - 1) }

    func goToPage(_ requested: Int) {
        guard let entry = current, state.mode == .reading else { return }
        let target = Int(BookMath.clamp(Double(requested), 0, Double(entry.pages.count - 1)))
        guard target != pageIndex else { return }
        closeTerm()
        let wantTurned = (target + 1) / 2
        let nowTurned = (0..<entry.node.leafCount).filter { entry.node.leafProgress($0) >= 0.5 }.count
        let direction = wantTurned > nowTurned ? 1 : -1
        let diff = abs(wantTurned - nowTurned)
        pageIndex = target
        panZ = -99
        ensureTextures(entry, around: target, immediate: false)
        if diff > 0 {
            let stagger = min(0.1, 0.55 / Double(max(1, diff)))
            let duration = diff > 2 ? 0.55 : 0.85
            for k in 0..<diff {
                let leaf = direction > 0 ? nowTurned + k : nowTurned - 1 - k
                animateLeaf(entry, leaf, to: direction > 0 ? 1 : 0, duration: duration, delay: Double(k) * stagger)
            }
        }
        moveCamera(readTarget(target), duration: diff > 0 ? 0.9 : 0.7)
        afterNavigate()
    }

    func goToBase(pageID: String) {
        guard let entry = current, let i = entry.pages.firstIndex(where: { $0.baseID == pageID }) else { return }
        goToPage(i)
    }

    private func animateLeaf(_ entry: Entry, _ leaf: Int, to: Double, duration: Double, delay: Double) {
        guard leaf >= 0, leaf < entry.node.leafCount else { return }
        let key = leaf
        tweens.cancel(leafTweens[key])
        let from = entry.node.leafProgress(leaf)
        leafTweens[key] = tweens.add(duration: duration, delay: delay, ease: .inOutSine, onUpdate: { t in
            entry.node.setLeafProgress(leaf, BookMath.lerp(from, to, t))
            entry.node.layout()
        }, onDone: { [weak self] in
            entry.node.setLeafProgress(leaf, to)
            entry.node.layout()
            self?.leafTweens[key] = nil
        })
    }

    private func afterNavigate() {
        guard let entry = current, entry.pages.indices.contains(pageIndex) else { return }
        let phys = entry.pages[pageIndex]
        state.page = pageIndex
        state.basePageID = phys.baseID
        state.canPrev = pageIndex > 0
        state.canNext = pageIndex < entry.pages.count - 1
        state.revealed = recall.isPageRevealed(phys.id)
        ensureTextures(entry, around: pageIndex, immediate: false)
        post(.visit(bookID: entry.book.id, pageID: phys.baseID))
        emit()
    }

    func closeTerm() {
        // Terms arrive with the tap handling (Task 12); nothing is open yet.
    }

    // MARK: Recall and text size

    func setRecall(_ on: Bool) {
        var next = recall
        next.setEnabled(on)
        guard next != recall else { return }
        recall = next
        state.recall = recall.isEnabled
        state.revealed = false
        redrawVisible()
        emit()
    }

    func setLevel(_ level: RecallLevel) {
        var next = recall
        next.setLevel(level)
        guard next != recall else { return }
        recall = next
        state.level = level
        post(.preference(recallLevel: level, textSize: nil))
        state.revealed = false
        redrawVisible()
        emit()
    }

    func togglePageReveal() {
        guard let entry = current, entry.pages.indices.contains(pageIndex) else { return }
        let id = entry.pages[pageIndex].id
        if recall.isPageRevealed(id) { recall.hidePage(id) } else { recall.revealPage(id) }
        state.revealed = recall.isPageRevealed(id)
        redrawVisible()
        emit()
    }

    func setTextSize(_ size: ReaderTextSize) async {
        guard size != textSize else { return }
        textSize = size
        state.textSize = size
        post(.preference(recallLevel: nil, textSize: size))
        let keepBase = state.basePageID
        let wasReading = state.mode == .reading ? current?.book.id : nil
        await rebuild()
        menuLayout()
        if let wasReading, let entry = entries.first(where: { $0.book.id == wasReading }) {
            current = entry
            let index = max(0, entry.pages.firstIndex { $0.baseID == keepBase } ?? 0)
            pageIndex = index
            state.pageCount = entry.pages.count
            entry.node.root.position = SCNVector3Zero
            entry.node.root.eulerAngles = SCNVector3Zero
            for other in entries where other !== entry { other.node.root.position = SCNVector3(0, 0, -6) }
            setLeavesInstant(entry, page: index)
            entry.node.setCoverOpen(1)
            afterNavigate()
            moveCamera(readTarget(index), duration: 0)
        }
        emit()
    }

    // MARK: Focus

    func setFocus(_ on: Bool, silent: Bool = false) {
        guard state.focus != on else { return }
        state.focus = on
        let from = propsOpacity, to = on ? 0.0 : 1.0
        tweens.add(duration: 0.7, ease: .inOut) { [weak self] t in
            self?.setPropsOpacity(BookMath.lerp(from, to, t))
        }
        if current != nil, state.mode == .reading { moveCamera(readTarget(pageIndex, focus: on), duration: 0.9) }
        if !silent { emit() }
    }

    private func setPropsOpacity(_ v: Double) {
        propsOpacity = v
        desk.props.isHidden = v <= 0.02
        desk.props.opacity = CGFloat(v)
        desk.props.position = SCNVector3(0, Float(-(1 - v) * 0.6), 0)
    }

    // MARK: Page images

    private func key(_ entry: Entry, _ i: Int) -> String { "\(entry.book.id):\(i)" }

    private func options(_ entry: Entry, _ i: Int) -> PageRenderOptions {
        PageRenderOptions(
            face: i % 2 == 0 ? .front : .back, rtl: entry.book.isRightToLeft, subject: entry.book.subject.rawValue,
            recall: recall, revealAll: false
        )
    }

    /// The cached bitmap for page `i` (nil while it is still being drawn).
    func pageImage(_ entry: Entry, _ i: Int) -> PageImage? { cache[key(entry, i)] }

    /// Draws page `i` now, on this thread.
    private func renderNow(_ entry: Entry, _ i: Int) {
        let phys = entry.pages.indices.contains(i) ? entry.pages[i] : nil
        let result = PageRenderer.draw(phys, options(entry, i))
        let k = key(entry, i)
        cache[k] = PageImage(image: result.image, hits: result.hits)
        pending[k] = nil
    }

    /// Draws page `i` off the main thread and puts it on its leaf face when done.
    private func renderLater(_ entry: Entry, _ i: Int) {
        let k = key(entry, i)
        guard pending[k] == nil else { return }
        let token = generation
        pending[k] = token
        let phys = entry.pages.indices.contains(i) ? entry.pages[i] : nil
        let box = UncheckedBox((phys, options(entry, i)))
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = PageRenderer.draw(box.value.0, box.value.1)
            let done = UncheckedBox(PageImage(image: result.image, hits: result.hits))
            await MainActor.run {
                guard let self, self.pending[k] == token, token == self.generation else { return }
                self.pending[k] = nil
                self.cache[k] = done.value
                if self.assigned[entry.book.id]?.contains(i) == true { self.show(entry, i) }
            }
        }
    }

    private func show(_ entry: Entry, _ i: Int) {
        guard let page = cache[key(entry, i)] else { return }
        entry.node.setLeafImage(i / 2, front: i % 2 == 0, image: page.image)
    }

    /// Gives the leaves around page `i` their bitmaps and frees the ones far away (`_ensureTextures`).
    func ensureTextures(_ entry: Entry, around i: Int, immediate: Bool) {
        let n = entry.pages.count
        var want = Set<Int>()
        for k in (i - 3)...(i + 3) where k >= -1 && k <= n { want.insert(k) }
        var assignedNow = Set<Int>()
        for leaf in 0..<entry.node.leafCount {
            for front in [true, false] {
                let pi = leaf * 2 + (front ? 0 : 1)
                if want.contains(pi) {
                    assignedNow.insert(pi)
                    if cache[key(entry, pi)] == nil {
                        if immediate, abs(pi - i) <= 1 { renderNow(entry, pi) } else { renderLater(entry, pi) }
                    }
                    if cache[key(entry, pi)] != nil { show(entry, pi) }
                } else {
                    entry.node.setLeafImage(leaf, front: front, image: nil)
                }
            }
        }
        assigned[entry.book.id] = assignedNow
        for k in Array(cache.keys) where k.hasPrefix(entry.book.id + ":") {
            guard let pi = Int(k.dropFirst(entry.book.id.count + 1)) else { continue }
            if abs(pi - i) > 6 { cache[k] = nil }
        }
    }

    /// Draws every cached page of the open book again (recall state changed).
    func redrawVisible() {
        guard let entry = current else { return }
        generation += 1
        pending = [:]
        let prefix = entry.book.id + ":"
        for k in Array(cache.keys) where k.hasPrefix(prefix) {
            guard let pi = Int(k.dropFirst(prefix.count)) else { continue }
            // Keep the old bitmap on screen until the new one is ready.
            renderLater(entry, pi)
        }
    }

    // MARK: Commands and state

    func handle(_ command: SceneCommand) async {
        switch command {
        case .openBook(let id, let pageID): openBook(id: id, pageID: pageID)
        case .closeBook: closeBook()
        case .next: next()
        case .previous: previous()
        case .goTo(let id): goToBase(pageID: id)
        case .setRecall(let on): setRecall(on)
        case .setLevel(let level): setLevel(level)
        case .togglePageReveal: togglePageReveal()
        case .setTool: break // tools arrive in Task 12
        case .setFocus(let on): setFocus(on)
        case .setTextSize(let size): await setTextSize(size)
        case .setInsets(let top, let bottom): setInsets(top: top, bottom: bottom)
        case .setAppearance(let dark): setAppearance(dark: dark)
        case .setQuality(let q): setQuality(q)
        case .closeTerm: closeTerm()
        }
    }

    func emit() {
        var s = state
        s.page = state.page + 1
        s.pageCount = state.pageCount
        s.recall = recall.isEnabled
        s.level = recall.level
        s.textSize = textSize
        s.bookmarkPageID = current.flatMap { config.bookmarks[$0.book.id] }
        s.isRightToLeft = current?.book.isRightToLeft ?? false
        s.title = current?.book.title
        s.books = entries.map {
            SceneBookInfo(id: $0.book.id, title: $0.book.title, subject: $0.book.subject.rawValue, pages: $0.pages.count, isRightToLeft: $0.book.isRightToLeft)
        }
        post(.state(s))
    }

    // MARK: Frame loop

    /// Advances animations by `dt` seconds. Call once per display frame.
    func tick(dt: Double) {
        let step = min(0.05, dt)
        tweens.update(dt: step)
        if state.mode == .menu { hoverStep(dt: step) }
    }

    // MARK: Picking

    /// The book under a screen point (points in the view), for taps in the menu.
    func bookID(at point: CGPoint, in view: SCNSceneRenderer) -> String? {
        let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let n = node {
                if let entry = entries.first(where: { $0.node.root === n }) { return entry.book.id }
                node = n.parent
            }
        }
        return nil
    }
}
