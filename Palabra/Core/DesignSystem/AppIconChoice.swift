import Foundation

/// The home-screen icons offered in Settings → Appearance → App Icon.
///
/// `assetName` is the name of the `<assetName>.appiconset` in the asset catalog and of the entry in
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (project.yml); iOS stores it as the alternate icon name.
/// Those names are frozen once shipped: renaming one leaves the phone showing an icon the app no longer lists.
/// Recortes is the primary icon (`AppIcon`, the app's own look), so choosing it means `setAlternateIconName(nil)`; the first icon is now the `Clasico` alternate.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case recortes, clasico, medianoche, sol, pregunta, olivo, belleEpoque, frontera

    var id: String { rawValue }

    /// Asset-catalog name of the alternate icon set; `nil` for the original icon.
    var alternateName: String? {
        switch self {
        case .recortes: nil
        case .clasico: "Clasico"
        case .medianoche: "Medianoche"
        case .sol: "Sol"
        case .pregunta: "Pregunta"
        case .olivo: "Olivo"
        case .belleEpoque: "BelleEpoque"
        case .frontera: "Frontera"
        }
    }

    /// Imageset used to show the icon inside the app (an `.appiconset` cannot be loaded with `Image(_:)`).
    var previewAsset: String { "IconPreview" + (alternateName ?? "Recortes") }

    /// The icon's own name. A proper name, shown as written in both app languages.
    var title: String {
        switch self {
        case .recortes: "Recortes"
        case .clasico: "Clásico"
        case .medianoche: "Medianoche"
        case .sol: "Sol"
        case .pregunta: "Pregunta"
        case .olivo: "Olivo"
        case .belleEpoque: "Belle Époque"
        case .frontera: "Frontera"
        }
    }

    /// One line on its taste; a localisation key (English text).
    var tagline: String {
        switch self {
        case .recortes: "Paper cutouts, like the app"
        case .clasico: "The first icon"
        case .medianoche: "A day sky, a golden moon at night"
        case .sol: "Sunburst"
        case .pregunta: "A bold ¿"
        case .olivo: "Olive branches"
        case .belleEpoque: "Art Nouveau, 1900"
        case .frontera: "1899 wanted poster"
        }
    }

    /// The choice for what `UIApplication.alternateIconName` reports; `nil` or a name this build no longer lists is the original.
    init(alternateName: String?) {
        self = Self.allCases.first { $0.alternateName == alternateName && alternateName != nil } ?? .recortes
    }
}
