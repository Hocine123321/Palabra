import Foundation

/// Checks that an AI-formatted lesson says nothing the source text did not say. Pure and fast.
///
/// - A **number** (any run of digits, Arabic-Indic digits counted as the same digits) that is in the lesson but not in the
///   source is blocked: dates and figures are exactly what must never be invented.
/// - A **word** (3+ letters) that is not in the source is only a warning: formatting legitimately adds labels such as
///   "Causes" or "Timeline", and Arabic words change with prefixes and diacritics.
/// `transcriptionNotes` are the AI's own remarks about the source, so they are not checked.
enum LessonFaithfulness {
    struct Report: Equatable {
        var blockedNumbers: [String]
        var newWords: [String]

        /// True when nothing blocks saving the lesson as faithful. New words alone never block.
        var isClean: Bool { blockedNumbers.isEmpty }
    }

    static func check(_ lesson: Lesson, source: String) -> Report {
        let sourceNumbers = Set(numbers(in: source))
        let sourceStems = Set(words(in: source).flatMap(stems))
        var blocked: [String] = []
        var added: [String] = []
        var seenNumbers = Set<String>()
        var seenWords = Set<String>()
        for text in texts(of: lesson) {
            let plain = InlineMarkup.plainText(text)
            for number in numbers(in: plain) where !sourceNumbers.contains(number) && seenNumbers.insert(number).inserted {
                blocked.append(number)
            }
            for word in words(in: plain) where stems(word).isDisjoint(with: sourceStems) && seenWords.insert(word).inserted {
                added.append(word)
            }
        }
        return Report(blockedNumbers: blocked, newWords: added)
    }

    // MARK: Text

    private static func texts(of lesson: Lesson) -> [String] {
        var out = [lesson.title]
        if let summary = lesson.summary { out.append(summary) }
        for term in lesson.terms.values { out += [term.term, term.definition] }
        for page in lesson.pages {
            out.append(page.title)
            if let date = page.dateLabel { out.append(date) }
            for block in page.blocks { out += block.texts }
        }
        return out
    }

    /// Maximal runs of digits, written with Western digits.
    static func numbers(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            if let digit = westernDigit(scalar) {
                current.append(digit)
            } else if !current.isEmpty {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    private static func westernDigit(_ scalar: Unicode.Scalar) -> Character? {
        switch scalar.value {
        case 0x30...0x39: return Character(scalar)
        case 0x660...0x669: return Character(Unicode.Scalar(scalar.value - 0x660 + 0x30)!)
        case 0x6F0...0x6F9: return Character(Unicode.Scalar(scalar.value - 0x6F0 + 0x30)!)
        default: return nil
        }
    }

    /// Letter runs of three or more characters, lowercased, without Arabic diacritics and with the common letter variants merged.
    static func words(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        func flush() {
            if current.count >= 3 { out.append(current) }
            current = ""
        }
        for scalar in text.unicodeScalars {
            if isDiacritic(scalar) { continue }
            if CharacterSet.letters.contains(scalar) {
                current.unicodeScalars.append(contentsOf: fold(scalar))
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    private static func isDiacritic(_ scalar: Unicode.Scalar) -> Bool {
        (0x64B...0x65F).contains(scalar.value) || scalar.value == 0x670 || scalar.value == 0x640
    }

    private static func fold(_ scalar: Unicode.Scalar) -> String.UnicodeScalarView {
        switch scalar.value {
        case 0x623, 0x625, 0x622, 0x671: return "\u{627}".unicodeScalars // alef variants -> alef
        case 0x649: return "\u{64A}".unicodeScalars // alef maksura -> yeh
        case 0x629: return "\u{647}".unicodeScalars // teh marbuta -> heh
        default: return String(scalar).lowercased().unicodeScalars
        }
    }

    private static let prefixes = ["وال", "بال", "كال", "فال", "لل", "ال", "و", "ب", "ل", "ف", "ك"]

    /// The word and what it becomes with an Arabic prefix removed, so "الاستعمار" and "استعمار" meet.
    private static func stems(_ word: String) -> Set<String> {
        var out: Set<String> = [word]
        for prefix in prefixes where word.hasPrefix(prefix) && word.count - prefix.count >= 3 {
            out.insert(String(word.dropFirst(prefix.count)))
        }
        return out
    }
}
