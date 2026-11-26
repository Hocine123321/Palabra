import UIKit
import UniformTypeIdentifiers

/// Opens the system document picker for a library file. The picker hands over a COPY of the file inside the app (so no
/// security-scoped access or iCloud provider is involved afterwards) and accepts any file: a `.palabra` file is
/// recognised by its content, not by a type the system may not have registered (a sideloaded app's types can be late).
///
/// It is presented from UIKit rather than with SwiftUI's `.fileImporter`, which can stay silent when it is opened a
/// second time from inside a `Form`.
@MainActor
final class LibraryFilePicker: NSObject, UIDocumentPickerDelegate {
    private static var current: LibraryFilePicker?
    private var onPick: ((URL) -> Void)?

    static func present(onPick: @escaping (URL) -> Void) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        let owner = LibraryFilePicker()
        owner.onPick = onPick
        picker.delegate = owner
        current = owner
        guard let top = topViewController() else {
            current = nil
            return
        }
        top.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let handler = onPick
        Self.current = nil
        if let url = urls.first { handler?(url) }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Self.current = nil
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
