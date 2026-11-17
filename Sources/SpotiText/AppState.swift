import AppKit
import Combine
import Translation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var playerState: PlayerState = .notRunning
    @Published private(set) var track: TrackInfo?
    @Published private(set) var lyrics: LyricsState = .idle
    @Published private(set) var lyricsID: Int?
    @Published private(set) var candidates: [LyricsRecord] = []
    @Published private(set) var candidatesLoading = false

    @Published private(set) var romanizations: [Int: String] = [:]
    @Published private(set) var translations: [Int: String] = [:]
    @Published private(set) var translationStatus: String?
    @Published private(set) var missingTranslationLanguages: [Locale.Language] = []
    @Published private(set) var installedTranslationLanguages: [Locale.Language] = []
    @Published private(set) var downloadableTranslationLanguages: [Locale.Language] = []
    private let languageDownloader = LanguageDownloader()
    private var translationTask: Task<Void, Never>?
    private var attemptedDownloads: Set<String> = []

    @Published var offset: Double {
        didSet { UserDefaults.standard.set(offset, forKey: "offset") }
    }
    @Published var fontSize: Double {
        didSet {
            UserDefaults.standard.set(fontSize, forKey: "fontSize")
            updateLyricsWidth()
        }
    }
    @Published private(set) var lyricsTwoRowWidth: CGFloat = 0
    @Published var backgroundHex: String {
        didSet { UserDefaults.standard.set(backgroundHex, forKey: "backgroundHex") }
    }
    @Published var backgroundOpacity: Double {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: "backgroundOpacity") }
    }
    @Published var blur: Double {
        didSet { UserDefaults.standard.set(blur, forKey: "blur") }
    }
    @Published var controlsOnHoverOnly: Bool {
        didSet { UserDefaults.standard.set(controlsOnHoverOnly, forKey: "controlsOnHoverOnly") }
    }
    @Published var locked: Bool {
        didSet { UserDefaults.standard.set(locked, forKey: "locked") }
    }
    @Published var wordHighlight: Bool {
        didSet { UserDefaults.standard.set(wordHighlight, forKey: "wordHighlight") }
    }
    @Published var showRomanization: Bool {
        didSet { UserDefaults.standard.set(showRomanization, forKey: "showRomanization") }
    }
    @Published var showTranslation: Bool {
        didSet {
            UserDefaults.standard.set(showTranslation, forKey: "showTranslation")
            if showTranslation { requestTranslation() }
        }
    }
    @Published var autoDownloadLanguages: Bool {
        didSet {
            UserDefaults.standard.set(autoDownloadLanguages, forKey: "autoDownloadLanguages")
            if autoDownloadLanguages { attemptedDownloads = []; refreshTranslation() }
        }
    }
    @Published var showSettings = false
    @Published var userHidden = false
    @Published var scrubPosition: Double?
    @Published var hovering = false

    private var anchorPosition: Double = 0
    private var anchorDate = Date()

    private let spotify = SpotifyClient()
    private let lyricsService = LyricsService()
    private var cache: [String: (LyricsState, Int?)] = [:]
    private var translationCache: [String: [Int: String]] = [:]
    private var lyricsTask: Task<Void, Never>?
    private var candidatesTask: Task<Void, Never>?
    private var timer: Timer?

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "offset": 0.0, "fontSize": 30.0,
            "backgroundHex": "#000000", "backgroundOpacity": 0.45, "blur": 1.0,
            "controlsOnHoverOnly": false, "locked": false,
            "wordHighlight": true, "autoDownloadLanguages": true, "showRomanization": false, "showTranslation": false,
        ])
        offset = defaults.double(forKey: "offset")
        fontSize = defaults.double(forKey: "fontSize")
        backgroundHex = defaults.string(forKey: "backgroundHex") ?? "#000000"
        backgroundOpacity = defaults.double(forKey: "backgroundOpacity")
        blur = defaults.double(forKey: "blur")
        controlsOnHoverOnly = defaults.bool(forKey: "controlsOnHoverOnly")
        locked = defaults.bool(forKey: "locked")
        wordHighlight = defaults.bool(forKey: "wordHighlight")
        autoDownloadLanguages = defaults.bool(forKey: "autoDownloadLanguages")
        showRomanization = defaults.bool(forKey: "showRomanization")
        showTranslation = defaults.bool(forKey: "showTranslation")
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func position(at date: Date) -> Double {
        playbackPosition(at: date) + offset
    }

    func playbackPosition(at date: Date) -> Double {
        let elapsed = playerState == .playing ? date.timeIntervalSince(anchorDate) : 0
        return anchorPosition + elapsed
    }

    static let offsetStep = 0.25

    func adjustOffset(by delta: Double) {
        offset = min(max(((offset + delta) * 100).rounded() / 100, -10), 10)
    }

    func seek(to seconds: Double) {
        spotify.seek(to: seconds)
        anchorPosition = seconds
        anchorDate = Date()
        scrubPosition = nil
    }

    func poll() {
        let snapshot = spotify.fetch()
        anchorPosition = snapshot.position
        anchorDate = Date()

        if playerState != snapshot.state { playerState = snapshot.state }
        if track != snapshot.track {
            track = snapshot.track
            loadLyrics()
        }
    }

    func send(_ command: SpotifyClient.Command) {
        spotify.send(command)
        poll()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.poll()
        }
    }

    private func loadLyrics() {
        lyricsTask?.cancel()
        candidatesTask?.cancel()
        candidates = []
        candidatesLoading = false
        guard let track else {
            setLyrics(.idle, id: nil)
            return
        }
        guard track.id.hasPrefix("spotify:track:") || track.id.hasPrefix("spotify:local:") else {
            setLyrics(.notFound, id: nil)
            return
        }
        if let (cached, id) = cache[track.id] {
            setLyrics(cached, id: id)
            return
        }

        setLyrics(.loading, id: nil)
        let preferredID = Self.savedChoices[track.id]
        lyricsTask = Task { [weak self, lyricsService] in
            let (result, id) = await lyricsService.fetch(track, preferredID: preferredID)
            guard !Task.isCancelled, let self, self.track == track else { return }
            self.setLyrics(result, id: id)
            if case .error = result { return }
            self.cache[track.id] = (result, id)
        }
    }

    private func updateLyricsWidth() {
        guard case .synced(let lines) = lyrics else {
            lyricsTwoRowWidth = 0
            return
        }
        lyricsTwoRowWidth = LyricsMetrics.minWidthForTwoRows(lines.map(\.text), fontSize: fontSize) + 8
    }

    private func setLyrics(_ state: LyricsState, id: Int?) {
        lyrics = state
        lyricsID = id
        updateLyricsWidth()
        translationStatus = nil
        missingTranslationLanguages = []
        translationTask?.cancel()
        if case .synced(let lines) = state {
            romanizations = Romanizer.romanize(lines)
            translations = translationCache[translationKey] ?? [:]
            if showTranslation { requestTranslation() }
        } else {
            romanizations = [:]
            translations = [:]
        }
    }

    private static var savedChoices: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: "lyricsChoices") as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "lyricsChoices") }
    }

    func loadCandidates() {
        guard let track, candidates.isEmpty, !candidatesLoading else { return }
        candidatesLoading = true
        candidatesTask = Task { [weak self, lyricsService] in
            let found = (try? await lyricsService.candidates(for: track)) ?? []
            guard !Task.isCancelled, let self, self.track == track else { return }
            self.candidates = found
            self.candidatesLoading = false
        }
    }

    func choose(_ record: LyricsRecord) {
        guard let track else { return }
        let state = record.state ?? .notFound
        Self.savedChoices[track.id] = record.id
        cache[track.id] = (state, record.id)
        setLyrics(state, id: record.id)
    }

    private var translationKey: String { "\(track?.id ?? "")#\(lyricsID ?? 0)" }

    func refreshTranslation() {
        if !missingTranslationLanguages.isEmpty { translations = [:] }
        requestTranslation()
        loadTranslationLanguages()
    }

    private func requestTranslation() {
        guard showTranslation, case .synced(let lines) = lyrics, translations.isEmpty else { return }
        let key = translationKey
        translationTask?.cancel()
        translationStatus = "Translating…"
        translationTask = Task { [weak self] in
            await self?.translate(lines, key: key)
        }
    }

    private func translate(_ lines: [LyricLine], key: String) async {
        let target = Self.ukrainian
        var groups: [String: [Int]] = [:]
        for (index, language) in Romanizer.lineLanguages(lines) where language != .ukrainian {
            groups[language.rawValue, default: []].append(index)
        }

        var result: [Int: String] = [:]
        var missing: [Locale.Language] = []
        for (code, indices) in groups.sorted(by: { $0.value.count > $1.value.count }) {
            let source = Locale.Language(identifier: code)
            switch await LanguageAvailability().status(from: source, to: target) {
            case .installed:
                let session = TranslationSession(installedSource: source, target: target)
                let requests = indices.map {
                    TranslationSession.Request(sourceText: lines[$0].text, clientIdentifier: String($0))
                }
                if let responses = try? await session.translations(from: requests) {
                    for response in responses {
                        if let id = response.clientIdentifier, let index = Int(id) { result[index] = response.targetText }
                    }
                }
            case .supported:
                missing.append(source)
            default:
                break
            }
        }

        guard !Task.isCancelled, key == translationKey else { return }
        translations = result
        missingTranslationLanguages = missing
        if missing.isEmpty {
            translationCache[key] = result
            translationStatus = groups.isEmpty ? "Lyrics are already in Ukrainian." : nil
            return
        }
        let names = missing.map(Self.languageName).joined(separator: ", ")
        translationStatus = "Missing language: \(names)."
        if autoDownloadLanguages, let next = missing.first(where: { !attemptedDownloads.contains($0.minimalIdentifier) }) {
            downloadLanguage(next)
        }
    }

    func downloadLanguage(_ source: Locale.Language) {
        attemptedDownloads.insert(source.minimalIdentifier)
        showSettings = false
        translationStatus = "Downloading \(Self.languageName(source))…"
        languageDownloader.download(from: source, to: Self.ukrainian) { [weak self] success in
            guard let self else { return }
            if success {
                self.translations = [:]
                self.translationCache[self.translationKey] = nil
                self.requestTranslation()
            } else {
                self.translationStatus = "\(Self.languageName(source)) wasn't downloaded."
            }
            self.loadTranslationLanguages()
        }
    }

    func loadTranslationLanguages() {
        Task { [weak self] in
            let availability = LanguageAvailability()
            var installed: [Locale.Language] = []
            var downloadable: [Locale.Language] = []
            for language in await availability.supportedLanguages
            where language.minimalIdentifier != Self.ukrainian.minimalIdentifier {
                switch await availability.status(from: language, to: Self.ukrainian) {
                case .installed: installed.append(language)
                case .supported: downloadable.append(language)
                default: break
                }
            }
            let byName = { (a: Locale.Language, b: Locale.Language) in Self.languageName(a) < Self.languageName(b) }
            self?.installedTranslationLanguages = installed.sorted(by: byName)
            self?.downloadableTranslationLanguages = downloadable.sorted(by: byName)
        }
    }

    private static let ukrainian = Locale.Language(identifier: "uk")

    static func languageName(_ language: Locale.Language) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: language.maximalIdentifier)
            ?? language.minimalIdentifier
    }
}
