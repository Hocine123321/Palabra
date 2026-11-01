import Foundation

/// The easings of `web/books3d/src/tween.js`.
enum Ease: String, CaseIterable {
    case linear, inOut, out, inOutSine, outBack

    func apply(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .inOut:
            return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .out:
            return 1 - pow(1 - t, 3)
        case .inOutSine:
            return -(cos(Double.pi * t) - 1) / 2
        case .outBack:
            let c1 = 1.4
            let c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        }
    }
}

/// One running animation. Only `Tweens` creates and advances it.
final class Tween {
    fileprivate var time: Double
    fileprivate let duration: Double
    fileprivate let ease: Ease
    fileprivate let onUpdate: (Double) -> Void
    fileprivate let onDone: (() -> Void)?
    fileprivate(set) var isDead = false

    fileprivate init(time: Double, duration: Double, ease: Ease, onUpdate: @escaping (Double) -> Void, onDone: (() -> Void)?) {
        self.time = time
        self.duration = duration
        self.ease = ease
        self.onUpdate = onUpdate
        self.onDone = onDone
    }
}

/// A tiny tween engine driven by the render loop (port of `tween.js`). `timeScale` shrinks every duration and delay added
/// afterwards, which is how Reduce Motion turns flights into jumps (0.001).
final class Tweens {
    var timeScale: Double = 1
    private var list: [Tween] = []

    var isActive: Bool { list.contains { !$0.isDead } }

    @discardableResult
    func add(
        duration: Double,
        delay: Double = 0,
        ease: Ease = .inOut,
        onUpdate: @escaping (Double) -> Void,
        onDone: (() -> Void)? = nil
    ) -> Tween {
        let scaledDelay = delay * timeScale
        let tween = Tween(
            time: -scaledDelay,
            duration: max(0.0001, duration * timeScale),
            ease: ease,
            onUpdate: onUpdate,
            onDone: onDone
        )
        list.append(tween)
        return tween
    }

    /// Advances every tween by `dt` seconds. A tween added from inside a callback is advanced in the same pass, as in the JS.
    func update(dt: Double) {
        var i = 0
        while i < list.count {
            let tween = list[i]
            i += 1
            if tween.isDead { continue }
            tween.time += dt
            if tween.time < 0 { continue }
            let progress = min(1, tween.time / tween.duration)
            tween.onUpdate(tween.ease.apply(progress))
            if progress >= 1 {
                tween.isDead = true
                tween.onDone?()
            }
        }
        list.removeAll { $0.isDead }
    }

    /// A cancelled tween never calls `onUpdate` or `onDone` again.
    func cancel(_ tween: Tween?) {
        tween?.isDead = true
    }

    func cancelAll() {
        list.forEach { $0.isDead = true }
        list.removeAll()
    }
}
