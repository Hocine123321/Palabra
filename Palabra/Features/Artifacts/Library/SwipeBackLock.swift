import SwiftUI
import UIKit

/// Switches off the edge swipe that goes back to the previous screen while `locked` is true, so a swipe inside a full-screen app
/// (a game, a slider) is the app's and never leaves the screen. Switched back on when `locked` turns false or the view goes away.
struct SwipeBackLock: UIViewControllerRepresentable {
    let locked: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.locked = locked
        controller.apply()
    }

    final class Controller: UIViewController {
        var locked = false

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        func apply() {
            // SwiftUI may attach this controller to the navigation controller a moment after the first update.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.navigationController?.interactivePopGestureRecognizer?.isEnabled = !self.locked
            }
        }
    }
}
