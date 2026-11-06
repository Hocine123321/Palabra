import CoreGraphics
import Foundation
import SceneKit
import simd
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
    var freeView = true
    var enhancements = true
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
    let enhancements = SceneEnhancements()
    private(set) var enhancementsEnabled = true
    let tweens = Tweens()
    private let booksRoot = SCNNode()

    // MARK: State

    var state = SceneState()
    private(set) var entries: [Entry] = []
    private(set) var current: Entry?
    /// 0-based index of the page being read.
    var pageIndex = 0
    var recall: RecallState
    private(set) var textSize: ReaderTextSize
    private(set) var quality: SceneQuality
    private(set) var isDark = false
    private(set) var insets = (top: 0.0, bottom: 0.0)
    var panZ = 0.0
    private(set) var panLimit = 0.0
    private(set) var pxPerZ = 1.0
    private(set) var isLoaded = false
    var hoverBook: String?
    var activeTermID: String?
    /// Set by the view: what is under a screen point (needs a renderer).
    weak var picker: ScenePicker?
    var drag: PointerDrag?
    var peekLeaf: Int?
    /// Free view: what the fingers asked for, what is drawn (it chases the target), and the glide after a release.
    var free = FreeView()
    var freeShown = (zoom: 1.0, pan: SIMD2<Double>.zero)
    var freeDamp = (zoom: SmoothDamp(), x: SmoothDamp(), y: SmoothDamp())
    var freeInertia: Inertia?
    var freeEnabled = true
    /// Study tools (the lens, the ruler and the bookmark card), their root, and what the lens and ruler are doing.
    let toolsRoot = SCNNode()
    let lens = LensNode()
    let ruler = ToolFactory.ruler()
    let bookmarkTool = ToolFactory.bookmark()
    var lensPos = (x: 0.0, z: 0.0)
    var lensShownKey: String?
    var lensImageCache: [String: CGImage] = [:]
    var lensPending = Set<String>()
    var rulerZ = -0.25
    var bandOn = false
    var tools: [String: ToolNode] { ["lens": lens.tool, "ruler": ruler, "bookmark": bookmarkTool] }
    var sink: ((SceneMessage) -> Void)?
    /// Called when the view should switch its render quality.
    var onQualityChange: ((SceneQuality) -> Void)?

    var config: NativeSceneConfig
    private var closeAfterOpen = false
    private var cameraTween: Tween?
    private var shiftTween: Tween?
    private var propsOpacity = 1.0
    var leafTweens: [Int: Tween] = [:]
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
        scene.rootNode.addChildNode(enhancements.root)
        enhancements.install(on: desk)
        enhancementsEnabled = config.enhancements
        for tool in [lens.tool, ruler, bookmarkTool] { toolsRoot.addChildNode(tool.root) }
        toolsRoot.isHidden = true
        scene.rootNode.addChildNode(toolsRoot)
        scene.rootNode.addChildNode(camera.node)
        scene.background.contents = SceneLighting.background(dark: false)
        tweens.timeScale = config.reducedMotion ? 0.001 : 1
        freeEnabled = config.freeView
        state.textSize = textSize
        state.level = recall.level
        lighting.setShadows(quality != .saver)
    }

    func leafTweenIsRunning(_ leaf: Int) -> Bool { leafTweens[leaf].map { !$0.isDead } ?? false }

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

    func post(_ message: SceneMessage) { sink?(message) }

    /// Re-runs pagination for every book (text size changed, or first load).
    private func rebuild() async {
        rebuildToken += 1
        let token = rebuildToken
        for entry in entries { entry.node.root.removeFromParentNode() }
        entries = []
        enhancements.resetBookShadows()
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
            enhancements.addBookShadow(for: node.root, mirrored: style.rtl)
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
        let next = (max(0, top), max(0, bottom))
        guard next != insets else { return }
        insets = next
        guard isLoaded else {
            camera.setShift(metrics.projectionShift)
            return
        }
        // The controls changed (Focus Mode, the recall bar, the menu coming back): the picture eases to the new view window and
        // framing instead of jumping by a few dozen points.
        settleCamera(duration: Self.settleDuration)
    }

    /// Puts the camera where the current mode wants it, without animating. Used when the window itself changes size, where the
    /// whole layout changes with it and an eased move would show the old framing stretched. Does nothing while a book opens or
    /// closes: the move ends with `reframeAfterTransition`.
    private func reframe() {
        switch state.mode {
        case .reading: moveCamera(readTarget(pageIndex), duration: 0)
        case .menu: frameMenu(animated: false)
        default: break
        }
    }

    // MARK: Camera

    /// How long the camera takes to adjust to new controls or a new size once a book is at rest.
    static let settleDuration = 0.4

    /// Eases the view window, and at rest the camera pose, to what the current mode and insets ask for. During an open or a close
    /// the move owns the camera pose, so only the view window eases (it is independent of the path) and the pose is corrected
    /// when the move has finished (`reframeAfterTransition`).
    private func settleCamera(duration: Double) {
        let shiftTo = metrics.projectionShift
        let animate = duration > 0 && !config.reducedMotion
        tweens.cancel(shiftTween)
        if animate {
            let shiftFrom = camera.shift
            shiftTween = tweens.add(duration: duration, ease: .inOut) { [weak self] t in
                self?.camera.setShift(BookMath.lerp(shiftFrom, shiftTo, t))
            }
        } else {
            camera.setShift(shiftTo)
        }
        // A move already under way (Focus Mode takes 0.9 s) keeps its pace: it is re-aimed at the framing for the new controls
        // rather than cut short to the settle time.
        let moving = cameraTween.map { !$0.isDead } ?? false
        let pace = animate ? (moving ? max(duration, 0.9) : duration) : 0
        switch state.mode {
        case .reading: moveCamera(readTarget(pageIndex), duration: pace)
        case .menu: moveCamera(Framing.menu(metrics), duration: pace)
        default: break
        }
    }

    /// Called when an open or close has finished. The size or the controls may have changed during it, and the move was aimed
    /// at the framing of the moment it started, so the camera and the view window ease the last bit to the framing the mode
    /// wants now. When nothing changed this does nothing. It never jumps.
    private func reframeAfterTransition() {
        let wanted: CameraPose
        switch state.mode {
        case .reading: wanted = readTarget(pageIndex)
        case .menu: wanted = Framing.menu(metrics)
        default: return
        }
        let closeEnough = Self.samePose(wanted, camera.pose) && abs(camera.shift - metrics.projectionShift) < 0.5
        guard !closeEnough else { return }
        settleCamera(duration: Self.settleDuration)
    }

    /// Poses closer than a millimetre-ish are the same pose (the spline ends within floating point error of its last keyframe).
    static func samePose(_ a: CameraPose, _ b: CameraPose, tolerance: Double = 0.002) -> Bool {
        simd_length(a.position - b.position) < tolerance && simd_length(a.look - b.look) < tolerance
    }

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

    /// Moves the camera along `path` as ONE tween, so it never stalls between legs. The path starts from wherever the camera
    /// is now (an interrupted move continues from its current pose instead of jumping). `delay` holds the camera still first
    /// (on a close, until the leaves have turned back).
    func moveCamera(along path: CameraPath, delay: Double = 0, duration: Double) {
        tweens.cancel(cameraTween)
        guard duration > 0 else {
            camera.setPose(path.end)
            return
        }
        var poses = path.poses
        poses[0] = camera.pose
        let live = CameraPath(poses: poses, times: path.times)
        // Linear time: the path's own end tangents ease the start and the stop. An ease on top of that made the camera
        // sit still for the first quarter second after the tap and then rush.
        cameraTween = tweens.add(duration: duration, delay: delay, ease: .linear) { [weak self] t in
            self?.camera.setPose(live.pose(at: t))
        }
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
        resetFreeView(animated: false)
        current = entry
        toolsRoot.isHidden = false
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
        // With animation the reading pages are drawn off the main thread: they are not visible until the lid has lifted
        // (about half a second in) and drawing them here would be one long frame right as the camera starts to move.
        // With Reduce Motion there is no animation to protect, so they are ready at once.
        ensureTextures(entry, around: start, immediate: config.reducedMotion, prefetchPriority: .utility)
        let plan = BookTransition.open
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
        tweens.add(duration: plan.bookDuration, delay: plan.bookDelay, ease: .inOut) { t in
            root.position = SCNVector3(
                Float(BookMath.lerp(Double(fromPos.x), 0, t)), Float(sin(t * .pi) * 0.35), Float(BookMath.lerp(Double(fromPos.z), 0, t))
            )
            root.eulerAngles = SCNVector3(0, Float(BookMath.lerp(fromRY, 0, t)), 0)
        }
        // ONE camera move from the desk to the page, over the book, that lands as the lid does. (Two moves cancelled each other
        // and left the camera stalling and then rushing; a stop at the cover made the first leg six times longer than the second.)
        let reading = readTarget(start, focus: false)
        moveCamera(
            along: CameraPath.arc(from: camera.pose, to: reading, over: coverPose(entry), along: plan.cameraWaypoint),
            delay: plan.cameraDelay, duration: plan.cameraDuration
        )
        tweens.add(duration: plan.lidDuration, delay: plan.lidDelay, ease: .inOut, onUpdate: { t in entry.node.setCoverOpen(t) }, onDone: { [weak self] in
            guard let self else { return }
            self.state.mode = .reading
            self.reframeAfterTransition()
            self.afterNavigate()
            if self.closeAfterOpen {
                self.closeAfterOpen = false
                self.closeBook()
            }
        })
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
        returnTools()
        setFocus(false, silent: true)
        resetFreeView(animated: true)
        state.mode = .closing
        let turned = (0..<entry.node.leafCount).filter { entry.node.leafProgress($0) > 0.5 }
        let plan = BookTransition.close(turnedLeaves: turned.count)
        for (k, leaf) in turned.enumerated() {
            animateLeaf(entry, leaf, to: 0, duration: plan.leafDuration, delay: min(0.4, Double(k) * plan.leafStagger))
        }
        // Everything is placed on one timeline: the camera pulls back from the first frame and the book starts gliding home
        // while the lid is still closing, so nothing waits for anything else and nothing is cut at the end.
        tweens.add(duration: plan.lidDuration, delay: plan.lidDelay, ease: .inOut, onUpdate: { t in entry.node.setCoverOpen(1 - t) })
        menuTransitionBack(entry, plan: plan)
        moveCamera(
            along: CameraPath.arc(from: camera.pose, to: Framing.menu(metrics), over: coverPose(entry), along: plan.cameraWaypoint),
            delay: plan.cameraDelay, duration: plan.cameraDuration
        )
        tweens.add(duration: 0.0001, delay: plan.total, onUpdate: { _ in }, onDone: { [weak self] in
            guard let self else { return }
            self.current = nil
            self.toolsRoot.isHidden = true
            self.state.mode = .menu
            self.state.bookID = nil
            self.state.page = 0
            self.pageIndex = 0
            self.reframeAfterTransition()
            self.emit()
        })
        emit()
    }

    /// Every book glides to its slot on the desk; the one that was open is lifted a little on the way.
    private func menuTransitionBack(_ closed: Entry, plan: BookTransition) {
        for entry in entries {
            let from = entry.node.root.position
            let fromRY = Double(entry.node.root.eulerAngles.y)
            let lift = entry === closed ? 0.3 : 0.0
            // The book that was open waits for the lid; the others were slid aside by the open and come back at once.
            let delay = entry === closed ? plan.bookDelay : 0
            let duration = entry === closed ? plan.bookDuration : min(0.9, plan.total)
            tweens.add(duration: duration, delay: delay, ease: .inOut) { t in
                entry.node.root.position = SCNVector3(
                    Float(BookMath.lerp(Double(from.x), entry.menu.x, t)), Float(sin(t * .pi) * lift),
                    Float(BookMath.lerp(Double(from.z), entry.menu.z, t))
                )
                entry.node.root.eulerAngles = SCNVector3(0, Float(BookMath.lerp(fromRY, entry.menu.ry, t)), 0)
            }
        }
    }

    func setLeavesInstant(_ entry: Entry, page: Int) {
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
        free.pan = .zero
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

    func animateLeaf(_ entry: Entry, _ leaf: Int, to: Double, duration: Double, delay: Double) {
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
            if self?.enhancementFlags.haptics == true { Haptics.leafLanded() }
        })
    }

    func afterNavigate() {
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

    func openTerm(id: String) {
        guard let entry = current, entry.pages.indices.contains(pageIndex),
              let definition = entry.pages[pageIndex].glossary[id] else { return }
        activeTermID = id
        post(.term(id: id, term: InlineMarkup.plainText(definition.term), definition: InlineMarkup.plainText(definition.definition)))
        emit()
    }

    func closeTerm() {
        guard activeTermID != nil else { return }
        activeTermID = nil
        post(.termClose)
        emit()
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
        resetFreeView(animated: false)
        state.textSize = size
        post(.preference(recallLevel: nil, textSize: size))
        let keepBase = state.basePageID
        let wasReading = state.mode == .reading ? current?.book.id : nil
        if wasReading != nil { returnTools() }
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
        for (name, tool) in tools where state.tool != name {
            tool.root.isHidden = v <= 0.02
            tool.root.opacity = CGFloat(v)
            tool.root.position.y = tool.restPosition.y - Float((1 - v) * 0.6)
        }
    }

    // MARK: Page images

    func key(_ entry: Entry, _ i: Int) -> String { "\(entry.book.id):\(i)" }

    func options(_ entry: Entry, _ i: Int) -> PageRenderOptions {
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
    /// `priority` is lowered only while a book opens: seven pages drawn together must not compete with the render loop for the
    /// cores, and those pages are not needed until the lid has lifted. Page turns keep `.userInitiated`.
    private func renderLater(_ entry: Entry, _ i: Int, priority: TaskPriority = .userInitiated) {
        let k = key(entry, i)
        guard pending[k] == nil else { return }
        let token = generation
        pending[k] = token
        let phys = entry.pages.indices.contains(i) ? entry.pages[i] : nil
        let box = UncheckedBox((phys, options(entry, i)))
        Task.detached(priority: priority) { [weak self] in
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
    func ensureTextures(_ entry: Entry, around i: Int, immediate: Bool, prefetchPriority: TaskPriority = .userInitiated) {
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
                        if immediate, abs(pi - i) <= 1 { renderNow(entry, pi) } else { renderLater(entry, pi, priority: prefetchPriority) }
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
        lensRefresh(force: true)
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
        case .setTool(let name): setTool(name)
        case .setFreeView(let on): setFreeViewEnabled(on)
        case .setEnhancements(let on): setEnhancements(on)
        case .resetView: resetFreeView(animated: true)
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
        s.viewMoved = freeEnabled && free.isMoved
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
        settlePeek()
        stepFreeView(dt: step)
        updateLens()
        stepEnhancements(dt: step)
    }

    // MARK: Enhancement tier

    var enhancementFlags: EnhancementFlags {
        EnhancementFlags.resolve(
            enabled: enhancementsEnabled, quality: quality, reduceMotion: config.reducedMotion,
            moved: free.isMoved, reading: state.mode != .menu, dark: isDark
        )
    }

    func setEnhancements(_ on: Bool) {
        enhancementsEnabled = on
    }

    private func stepEnhancements(dt: Double) {
        let flags = enhancementFlags
        enhancements.update(
            dt: dt, flags: flags, dark: isDark, menu: state.mode == .menu, camera: camera, lighting: lighting, bulb: desk.bulbPosition
        )
        current?.node.stepRibbon(dt: dt, enabled: flags.sway)
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
