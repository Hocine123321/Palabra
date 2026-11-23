import Foundation

/// What colour a word names, and how light or deep ("azul claro").
struct ColorWordMatch: Equatable {
    var family: ColorFamily
    var shade: ColorShade
}

/// Recognises Spanish colour words on the device: a lookup table, never an AI call.
/// Matching ignores case and accents ("marrón" = "marron") and handles gender and number
/// ("roja", "rojos", "azules"). Up to three words: a colour plus shade words ("azul claro",
/// "verde oscuro", "azul marino"). Anything else ("rojo de ira", "blanco y negro") is not a match.
enum ColorWords {
    static func match(_ raw: String) -> ColorWordMatch? {
        let tokens = WordKey.search(raw).split(separator: " ").map(String.init)
        guard (1...3).contains(tokens.count), let first = family(of: tokens[0]) else { return nil }
        var result = ColorWordMatch(family: first, shade: .normal)
        for token in tokens.dropFirst() {
            if lightWords.contains(token) {
                result.shade = .light
            } else if deepWords.contains(token) {
                result.shade = .deep
            } else if plainWords.contains(token) {
                continue
            } else if let named = namedShades[token], named.from == first {
                result = named.match
            } else {
                return nil
            }
        }
        return result
    }

    // MARK: Table (accent-folded, masculine singular)

    private static let table: [String: ColorFamily] = [
        "rojo": .red, "carmesi": .red, "escarlata": .red, "colorado": .red, "rojizo": .red,
        "naranja": .orange, "anaranjado": .orange,
        "amarillo": .yellow, "limon": .yellow, "amarillento": .yellow,
        "verde": .green, "verdoso": .green, "esmeralda": .green,
        "turquesa": .teal, "aguamarina": .teal, "cian": .teal,
        "celeste": .lightBlue,
        "azul": .blue, "azulado": .blue,
        "anil": .navy,
        "morado": .purple, "purpura": .purple, "violeta": .purple, "violaceo": .purple,
        "lila": .lavender, "lavanda": .lavender,
        "rosa": .pink, "rosado": .pink, "rosaceo": .pink, "fucsia": .pink, "magenta": .pink,
        "granate": .maroon, "burdeos": .maroon, "bordo": .maroon, "guinda": .maroon,
        "marron": .brown, "cafe": .brown, "castano": .brown, "pardo": .brown,
        "beige": .beige, "beis": .beige, "crema": .beige,
        "gris": .gray, "grisaceo": .gray,
        "negro": .black,
        "blanco": .white,
        "dorado": .gold, "oro": .gold,
        "plateado": .silver, "plata": .silver
    ]

    private static let lightWords: Set<String> = [
        "claro", "clara", "claros", "claras", "pastel", "palido", "palida", "palidos", "palidas"
    ]
    private static let deepWords: Set<String> = [
        "oscuro", "oscura", "oscuros", "oscuras", "fuerte", "fuertes", "intenso", "intensa",
        "intensos", "intensas", "profundo", "profunda"
    ]
    /// Words that describe the colour without changing which tint it gets.
    private static let plainWords: Set<String> = [
        "brillante", "brillantes", "vivo", "viva", "vivos", "vivas", "apagado", "apagada",
        "metalizado", "metalizada", "neon", "electrico", "electrica"
    ]
    /// Second words that name a different tint, valid only after the colour in `from`.
    private static let namedShades: [String: (from: ColorFamily, match: ColorWordMatch)] = [
        "marino": (.blue, ColorWordMatch(family: .navy, shade: .normal)),
        "cielo": (.blue, ColorWordMatch(family: .lightBlue, shade: .normal)),
        "oliva": (.green, ColorWordMatch(family: .green, shade: .deep)),
        "botella": (.green, ColorWordMatch(family: .green, shade: .deep)),
        "lima": (.green, ColorWordMatch(family: .lime, shade: .normal))
    ]

    private static func family(of token: String) -> ColorFamily? {
        for candidate in candidates(token) {
            if let family = table[candidate] { return family }
        }
        return nil
    }

    /// The word itself, then with the plural dropped ("rojas" → "roja", "azules" → "azul"),
    /// then with the feminine ending turned masculine ("roja" → "rojo").
    private static func candidates(_ token: String) -> [String] {
        var out = [token]
        var stems = [token]
        if token.count > 3, token.hasSuffix("es") {
            let stem = String(token.dropLast(2))
            out.append(stem)
            stems.append(stem)
        }
        if token.count > 3, token.hasSuffix("s") {
            let stem = String(token.dropLast())
            out.append(stem)
            stems.append(stem)
        }
        for stem in stems where stem.count > 2 && stem.hasSuffix("a") {
            out.append(String(stem.dropLast()) + "o")
        }
        return out
    }
}
