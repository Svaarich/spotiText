import Foundation
import NaturalLanguage

enum Romanizer {
    static func romanize(_ lines: [LyricLine]) -> [Int: String] {
        let isJapanese = lines.contains { containsKana($0.text) }
        var result: [Int: String] = [:]
        for (index, line) in lines.enumerated() where needsRomanization(line.text) {
            let latin = isJapanese ? japanese(line.text) : generic(line.text)
            if !latin.isEmpty, latin != line.text { result[index] = latin }
        }
        return result
    }

    static func needsRomanization(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            guard scalar.properties.isAlphabetic else { return false }
            let v = scalar.value
            let latin = v < 0x0250 || (0x1E00...0x1EFF).contains(v)
            let cyrillic = (0x0400...0x052F).contains(v)
            return !latin && !cyrillic
        }
    }

    static func language(of lines: [LyricLine]) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(lines.map(\.text).joined(separator: "\n"))
        return recognizer.dominantLanguage
    }

    static func lineLanguages(_ lines: [LyricLine]) -> [Int: NLLanguage] {
        let song = NLLanguageRecognizer()
        song.processString(lines.map(\.text).joined(separator: "\n"))
        let asian: Set<NLLanguage> = [.japanese, .korean, .simplifiedChinese, .traditionalChinese]
        let candidates = song.languageHypotheses(withMaximum: 4)
            .filter { $0.value > 0.05 && !asian.contains($0.key) }
            .map(\.key)
        let isJapaneseSong = lines.contains { containsKana($0.text) }

        var result: [Int: NLLanguage] = [:]
        for (index, line) in lines.enumerated() where !line.text.isEmpty {
            let text = line.text
            if containsKana(text) || (isJapaneseSong && containsHan(text)) {
                result[index] = .japanese
            } else if containsHangul(text) {
                result[index] = .korean
            } else if containsHan(text) {
                let recognizer = NLLanguageRecognizer()
                recognizer.languageConstraints = [.simplifiedChinese, .traditionalChinese]
                recognizer.processString(text)
                result[index] = recognizer.dominantLanguage ?? .simplifiedChinese
            } else {
                let recognizer = NLLanguageRecognizer()
                if !candidates.isEmpty { recognizer.languageConstraints = candidates }
                recognizer.processString(text)
                result[index] = recognizer.dominantLanguage ?? candidates.first ?? .english
            }
        }
        return result
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7AF).contains($0.value) || (0x1100...0x11FF).contains($0.value) }
    }

    private static func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    private static func japanese(_ text: String) -> String {
        let cfText = text as CFString
        let tokenizer = CFStringTokenizerCreate(
            nil, cfText, CFRange(location: 0, length: CFStringGetLength(cfText)),
            kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale)

        var parts: [String] = []
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
            if token.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                parts.append(latin)
            } else {
                parts.append(token)
            }
        }
        return parts.joined(separator: " ")
    }

    private static func generic(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        return mutable as String
    }
}
