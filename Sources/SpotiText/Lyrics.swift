import AppKit

struct LyricWord: Equatable {
    let time: Double
    let text: String
}

struct LyricLine: Equatable {
    let time: Double
    let text: String
    var end: Double?
    var words: [LyricWord] = []

    static func index(in lines: [LyricLine], at position: Double) -> Int {
        var low = 0, high = lines.count - 1, result = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    func wordTimings(nextLineTime: Double?) -> [LyricWord] {
        if !words.isEmpty { return words }

        var tokens = text.matches(of: #/\S+\s*/#).map { String($0.output) }
        if tokens.count == 1, text.count > 3 {
            tokens = text.map(String.init)
        }
        let totalCharacters = Double(tokens.reduce(0) { $0 + $1.count })
        guard totalCharacters > 0 else { return [] }

        let untilNext = (nextLineTime ?? time + 10) - time
        let duration = min(end.map { $0 - time } ?? untilNext, untilNext, max(1, totalCharacters * 0.08))

        var result: [LyricWord] = []
        var passed = 0.0
        for token in tokens {
            result.append(LyricWord(time: time + duration * passed / totalCharacters, text: token))
            passed += Double(token.count)
        }
        return result
    }
}

enum LyricsState: Equatable {
    case idle
    case loading
    case synced([LyricLine])
    case plain(String)
    case instrumental
    case notFound
    case error(String)
}

enum LRCParser {
    private static let timeTag = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"<(\d+):(\d+(?:[.:]\d+)?)>"#)

    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = timeTag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }

            let body = ns.substring(from: last.range.location + last.range.length)
            for match in matches {
                let time = seconds(ns, match)
                let (text, words) = parseWords(body, lineTime: time)
                lines.append(LyricLine(time: time, text: text, words: words))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private static func parseWords(_ body: String, lineTime: Double) -> (String, [LyricWord]) {
        let ns = body as NSString
        let matches = wordTag.matches(in: body, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else {
            return (body.trimmingCharacters(in: .whitespaces), [])
        }

        var words: [LyricWord] = []
        let prefix = ns.substring(to: matches[0].range.location)
        if !prefix.trimmingCharacters(in: .whitespaces).isEmpty {
            words.append(LyricWord(time: lineTime, text: prefix))
        }
        for (i, match) in matches.enumerated() {
            let start = match.range.location + match.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let text = ns.substring(with: NSRange(location: start, length: end - start))
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                words.append(LyricWord(time: seconds(ns, match), text: text))
            }
        }
        let text = words.map(\.text).joined().trimmingCharacters(in: .whitespaces)
        return (text, words)
    }

    private static func seconds(_ ns: NSString, _ match: NSTextCheckingResult) -> Double {
        let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
        let seconds = Double(ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
        return minutes * 60 + seconds
    }
}

enum LyricsFileParser {
    static func parse(_ yaml: String) -> [LyricLine] {
        struct Draft {
            var text = ""
            var start: Double?
            var end: Double?
            var words: [LyricWord] = []
        }

        var drafts: [Draft] = []
        var line: Draft?
        var word: (text: String, start: Double?)?
        var inLines = false
        var lineIndent: Int?
        var wordIndent: Int?

        func flushWord() {
            if let w = word, let start = w.start { line?.words.append(LyricWord(time: start, text: w.text)) }
            word = nil
        }
        func flushLine() {
            flushWord()
            if let l = line { drafts.append(l) }
            line = nil
        }

        for raw in yaml.components(separatedBy: .newlines) {
            let indent = raw.prefix { $0 == " " }.count
            var content = raw.trimmingCharacters(in: .whitespaces)
            if content.isEmpty { continue }

            if indent == 0, !content.hasPrefix("-") {
                inLines = content == "lines:"
                continue
            }
            guard inLines else { continue }

            var isNewItem = false
            if content.hasPrefix("- ") {
                isNewItem = true
                content = String(content.dropFirst(2))
            }
            guard let colon = content.firstIndex(of: ":") else { continue }
            let key = String(content[..<colon])
            let value = parseValue(String(content[content.index(after: colon)...]))

            if isNewItem {
                if lineIndent == nil { lineIndent = indent }
                if indent == lineIndent {
                    flushLine()
                    line = Draft()
                } else {
                    flushWord()
                    wordIndent = indent
                    word = ("", nil)
                }
            }

            if word != nil, let wordIndent, (isNewItem && indent == wordIndent) || indent > wordIndent {
                switch key {
                case "text": word?.text = value
                case "start_ms": word?.start = (Double(value) ?? 0) / 1000
                default: break
                }
            } else {
                switch key {
                case "text": line?.text = value
                case "start_ms": line?.start = (Double(value) ?? 0) / 1000
                case "end_ms": line?.end = (Double(value) ?? 0) / 1000
                default: break
                }
            }
        }
        flushLine()

        var lines = drafts.compactMap { d -> LyricLine? in
            guard let start = d.start else { return nil }
            return LyricLine(time: start, text: d.text.trimmingCharacters(in: .whitespaces), end: d.end, words: d.words)
        }.sorted { $0.time < $1.time }

        var withBreaks: [LyricLine] = []
        for (i, l) in lines.enumerated() {
            withBreaks.append(l)
            if let end = l.end, i + 1 < lines.count, lines[i + 1].time - end >= 5 {
                withBreaks.append(LyricLine(time: end + 0.3, text: ""))
            }
        }
        lines = withBreaks
        return lines
    }

    private static func parseValue(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if value.hasPrefix("\""), let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data) {
            return decoded
        }
        return value
    }
}

struct LyricsRecord: Decodable, Identifiable, Equatable {
    let id: Int
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let hasWordSync: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
    let lyricsfile: String?

    var hasSynced: Bool { syncedLyrics?.isEmpty == false }
    var hasWords: Bool { hasWordSync == true && lyricsfile?.isEmpty == false }

    var state: LyricsState? {
        if hasWords, let file = lyricsfile {
            let lines = LyricsFileParser.parse(file)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let synced = syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if instrumental == true { return .instrumental }
        if let plain = plainLyrics, !plain.isEmpty { return .plain(plain) }
        return nil
    }
}

final class LyricsService {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = ["User-Agent": "SpotiText/1.0 (macOS lyrics overlay)"]
        return URLSession(configuration: config)
    }()

    func fetch(_ track: TrackInfo, preferredID: Int?) async -> (LyricsState, Int?) {
        do {
            if let preferredID, let record = try await record(id: preferredID), let state = record.state {
                return (state, record.id)
            }

            let artist = Self.primaryArtist(track.artist)

            let exact = try? await get(track: track.name, artist: artist, album: track.album, duration: track.duration)
            if let exact, exact.hasSynced, let state = exact.state {
                return (state, exact.id)
            }

            var records = try await candidates(for: track)
            if let exact, !records.contains(where: { $0.id == exact.id }) {
                records.insert(exact, at: 0)
            }
            if let best = Self.best(of: records, duration: track.duration), let state = best.state {
                return (state, best.id)
            }
            return (.notFound, nil)
        } catch is CancellationError {
            return (.idle, nil)
        } catch {
            return (.error(error.localizedDescription), nil)
        }
    }

    func candidates(for track: TrackInfo) async throws -> [LyricsRecord] {
        let artist = Self.primaryArtist(track.artist)
        var records = (try? await search(["track_name": track.name, "artist_name": artist])) ?? []
        let cleaned = Self.cleanTitle(track.name)
        if cleaned != track.name {
            records += (try? await search(["track_name": cleaned, "artist_name": artist])) ?? []
        }
        records += (try? await search(["q": "\(cleaned) \(artist)"])) ?? []
        try Task.checkCancellation()

        var seen = Set<Int>()
        records = records.filter { seen.insert($0.id).inserted }

        func rank(_ r: LyricsRecord) -> (Int, Double) {
            let kind = r.hasWords ? 0 : r.hasSynced ? 1 : r.plainLyrics?.isEmpty == false ? 2 : 3
            return (kind, abs((r.duration ?? 0) - track.duration))
        }
        return records.sorted { rank($0) < rank($1) }
    }

    func record(id: Int) async throws -> LyricsRecord? {
        let (data, response) = try await session.data(from: URL(string: "https://lrclib.net/api/get/\(id)")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(LyricsRecord.self, from: data)
    }

    private func get(track: String, artist: String, album: String, duration: Double) async throws -> LyricsRecord? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(LyricsRecord.self, from: data)
    }

    private func search(_ query: [String: String]) async throws -> [LyricsRecord] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return (try? JSONDecoder().decode([LyricsRecord].self, from: data)) ?? []
    }

    private static func best(of records: [LyricsRecord], duration: Double) -> LyricsRecord? {
        func close(_ r: LyricsRecord, _ limit: Double) -> Bool { abs((r.duration ?? 0) - duration) <= limit }
        return records.first { $0.hasSynced && close($0, 3) }
            ?? records.first { $0.hasSynced && close($0, 10) }
            ?? records.first { $0.plainLyrics?.isEmpty == false && close($0, 3) }
            ?? records.first { $0.instrumental == true && close($0, 3) }
            ?? closest(records.filter(\.hasSynced), duration: duration)
            ?? closest(records.filter { $0.plainLyrics?.isEmpty == false }, duration: duration)
    }

    private static func closest(_ records: [LyricsRecord], duration: Double) -> LyricsRecord? {
        records.min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }
    }

    private static func primaryArtist(_ artist: String) -> String {
        artist.components(separatedBy: ", ").first ?? artist
    }

    static func cleanTitle(_ title: String) -> String {
        var result = title
        if let range = result.range(of: " - ") {
            result = String(result[..<range.lowerBound])
        }
        result = result.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }
}

enum LyricsMetrics {
    static func minWidthForTwoRows(_ texts: [String], fontSize: Double) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        return texts.map { minWidthForTwoRows($0, font: font) }.max() ?? 0
    }

    private static func minWidthForTwoRows(_ text: String, font: NSFont) -> CGFloat {
        func width(_ string: String) -> CGFloat {
            (string.trimmingCharacters(in: .whitespaces) as NSString).size(withAttributes: [.font: font]).width
        }
        let tokens = breakableTokens(text)
        guard tokens.count > 1 else { return ceil(width(text)) }
        var best = width(text)
        for split in 1..<tokens.count {
            let first = tokens[..<split].joined()
            let second = tokens[split...].joined()
            best = min(best, max(width(first), width(second)))
        }
        return ceil(best)
    }

    private static func breakableTokens(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text {
            if isCJK(character) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(character))
            } else if character == " " {
                current.append(character)
                tokens.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (0x3040...0x30FF).contains(v) || (0x3400...0x4DBF).contains(v)
                || (0x4E00...0x9FFF).contains(v) || (0xFF00...0xFFEF).contains(v)
        }
    }
}
