import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: AppState
    let window: WindowBridge

    private let cornerRadius: CGFloat = 18

    static let minimumSize = NSSize(width: 220, height: 50)
    private static let compactHeight: CGFloat = 150

    private var controlsOpacity: Double {
        if state.hovering || state.showSettings { return 1 }
        return state.controlsOnHoverOnly ? 0 : 0.5
    }

    private var needsTextShadow: Bool {
        state.backgroundOpacity < 0.3 && state.blur < 0.3
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < Self.compactHeight
            VStack(spacing: 6) {
                if !compact {
                    toolbar
                        .layoutPriority(1)
                }
                content
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .shadow(color: .black.opacity(needsTextShadow ? 0.9 : 0), radius: 3)
                if !compact, let track = state.track {
                    SeekBar(state: state, duration: track.duration)
                        .layoutPriority(1)
                        .opacity(controlsOpacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, compact ? 4 : 10)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background { background }
        .popover(isPresented: $state.showSettings, arrowEdge: .bottom) {
            SettingsView(state: state)
        }
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in window.move() }
                .onEnded { _ in window.end() }
        )
        .onHover { state.hovering = $0 }
    }

    private var background: some View {
        ZStack {
            if state.blur > 0 {
                BlurView(intensity: state.blur, cornerRadius: cornerRadius)
            }
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(hex: state.backgroundHex).opacity(state.backgroundOpacity))
        }
    }

    private var toolbar: some View {
        VStack(spacing: 4) {
            if let track = state.track {
                Text("\(track.name) — \(track.artist)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            buttons
        }
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            fullButtons
            playbackButtons
        }
        .frame(maxWidth: .infinity)
        .opacity(controlsOpacity)
        .animation(.easeInOut(duration: 0.15), value: controlsOpacity)
    }

    private let sideWidth: CGFloat = 104

    private var fullButtons: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                controlButton("xmark") {
                    state.hovering = false
                    state.userHidden = true
                }
                .help("Hide overlay (show again from the 🎤 menu)")
                controlButton("gearshape.fill") { state.showSettings.toggle() }
            }
            .frame(minWidth: sideWidth, maxWidth: .infinity, alignment: .leading)

            playbackButtons

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if state.track != nil { OffsetControl(state: state) }
            }
            .frame(minWidth: sideWidth, maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var playbackButtons: some View {
        if state.track != nil {
            HStack(spacing: 14) {
                controlButton("backward.fill") { state.send(.previous) }
                controlButton(state.playerState == .playing ? "pause.fill" : "play.fill", size: 15) {
                    state.send(.playPause)
                }
                controlButton("forward.fill") { state.send(.next) }
            }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat = 12, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var resizeGrip: some View {
        Color.clear
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in window.resize() }
                    .onEnded { _ in window.end() }
            )
    }

    @ViewBuilder
    private var content: some View {
        switch state.playerState {
        case .notRunning:
            message("Spotify isn't running")
        case .permissionDenied:
            message("Allow SpotiText to control Spotify:\nSystem Settings → Privacy & Security → Automation")
        case .stopped:
            message("Nothing is playing")
        case .playing, .paused:
            switch state.lyrics {
            case .idle, .loading:
                message("Looking for lyrics…")
            case .notFound:
                message("No lyrics found")
            case .instrumental:
                message("♪ Instrumental ♪")
            case .error(let text):
                message("Error: \(text)")
            case .plain(let text):
                ScrollView {
                    Text(text)
                        .font(.system(size: state.fontSize * 0.55, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            case .synced(let lines):
                SyncedLyricsView(state: state, lines: lines)
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: state.fontSize * 0.6, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.center)
    }
}

private struct SyncedLyricsView: View {
    @ObservedObject var state: AppState
    let lines: [LyricLine]

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 0.05)) { context in
                let position = state.position(at: context.date)
                LinesStack(
                    lines: lines,
                    current: LyricLine.index(in: lines, at: position),
                    position: position,
                    fontSize: fittingFontSize(in: geometry.size),
                    fadeEdges: geometry.size.height >= Self.singleLineHeight,
                    wordHighlight: state.wordHighlight,
                    romanizations: state.showRomanization ? state.romanizations : [:],
                    translations: state.showTranslation ? state.translations : [:])
            }
        }
    }

    private static let singleLineHeight: CGFloat = 90

    private func fittingFontSize(in size: CGSize) -> Double {
        let widthFactor = state.lyricsTwoRowWidth > 0 ? Double(size.width) / Double(state.lyricsTwoRowWidth) : 1
        let heightFactor = size.height < Self.singleLineHeight
            ? Double(size.height) / (state.fontSize * 1.3)
            : Double(size.height) * 0.76 / (state.fontSize * 2.6)
        return max(8, state.fontSize * min(1, widthFactor, heightFactor))
    }
}

private struct LinesStack: View {
    let lines: [LyricLine]
    let current: Int
    let position: Double
    let fontSize: Double
    let fadeEdges: Bool
    let wordHighlight: Bool
    let romanizations: [Int: String]
    let translations: [Int: String]

    private let smallScale = 0.6

    var body: some View {
        let low = max(-1, current - 15)
        let high = min(lines.count - 1, current + 15)
        LyricsLayout(focus: current - low, spacing: fontSize * 0.25) {
            ForEach(low...high, id: \.self) { index in
                line(index)
            }
        }
        .clipped()
        .mask(
            LinearGradient(stops: [
                .init(color: fadeEdges ? .clear : .black, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.88),
                .init(color: fadeEdges ? .clear : .black, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: current)
    }

    private func line(_ index: Int) -> some View {
        let isCurrent = index == current
        let scale = isCurrent ? 1 : smallScale
        let opacity: Double = isCurrent ? 1 : (index < current ? 0.3 : 0.5)
        let secondary = [romanizations[index], translations[index]].compactMap { $0 }
        return VStack(spacing: fontSize * 0.1) {
            mainText(index, isCurrent: isCurrent)
            ForEach(secondary, id: \.self) { text in
                Text(text)
                    .font(.system(size: fontSize * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .layoutValue(key: LineScale.self, value: scale)
        .transition(.opacity)
    }

    @ViewBuilder
    private func mainText(_ index: Int, isCurrent: Bool) -> some View {
        let text = index >= 0 ? lines[index].text : ""
        if text.isEmpty {
            if isCurrent, let dots = countdown(from: index) {
                Countdown(remaining: dots, size: fontSize)
            } else {
                styled(Text("♪"))
            }
        } else if isCurrent && wordHighlight {
            styled(Text(highlightedWords(index)))
        } else {
            styled(Text(text).foregroundStyle(.white))
        }
    }

    private func styled(_ text: Text) -> some View {
        text
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    private func highlightedWords(_ index: Int) -> AttributedString {
        let next = index + 1 < lines.count ? lines[index + 1].time : nil
        var result = AttributedString()
        for word in lines[index].wordTimings(nextLineTime: next) {
            var part = AttributedString(word.text)
            part.foregroundColor = word.time <= position ? Color.white : Color.white.opacity(0.4)
            result += part
        }
        return result
    }

    private func countdown(from index: Int) -> Int? {
        guard index + 1 < lines.count else { return nil }
        let start = index >= 0 ? lines[index].time : 0
        let next = lines[index + 1].time
        let remaining = next - position
        guard next - start >= 5, remaining > 0, remaining <= 3 else { return nil }
        return Int(remaining.rounded(.up))
    }
}

private struct Countdown: View {
    let remaining: Int
    let size: Double

    var body: some View {
        HStack(spacing: size * 0.35) {
            ForEach(0..<3, id: \.self) { dot in
                Circle()
                    .fill(.white.opacity(dot < remaining ? 1 : 0.2))
                    .frame(width: size * 0.32, height: size * 0.32)
            }
        }
        .frame(height: size * 1.2)
        .animation(.easeOut(duration: 0.3), value: remaining)
    }
}

private struct LineScale: LayoutValueKey {
    static let defaultValue: Double = 1
}

private struct LyricsLayout: Layout {
    var focus: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let itemProposal = ProposedViewSize(width: bounds.width, height: nil)
        var centers: [CGFloat] = []
        var heights: [CGFloat] = []
        var y: CGFloat = 0
        for subview in subviews {
            let height = subview.sizeThatFits(itemProposal).height
            let scaled = height * CGFloat(subview[LineScale.self])
            centers.append(y + scaled / 2)
            heights.append(height)
            y += scaled + spacing
        }
        guard !centers.isEmpty else { return }
        let focusY = centers[min(max(focus, 0), centers.count - 1)]

        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY + centers[index] - focusY),
                anchor: .center,
                proposal: ProposedViewSize(width: bounds.width, height: heights[index]))
        }
    }
}

private struct OffsetControl: View {
    @ObservedObject var state: AppState

    static func format(_ offset: Double) -> String {
        offset == 0 ? "0.00 s" : String(format: "%+.2f s", offset)
    }

    var body: some View {
        HStack(spacing: 2) {
            button("minus", help: "Lyrics later (−\(AppState.offsetStep) s)") {
                state.adjustOffset(by: -AppState.offsetStep)
            }
            Button { state.offset = 0 } label: {
                Text(Self.format(state.offset))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(state.offset == 0 ? 0.6 : 1))
                    .frame(minWidth: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Lyrics offset — click to reset")
            button("plus", help: "Lyrics earlier (+\(AppState.offsetStep) s)") {
                state.adjustOffset(by: AppState.offsetStep)
            }
        }
        .padding(.horizontal, 4)
        .background(Capsule().fill(.white.opacity(0.12)))
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct SettingsView: View {
    @ObservedObject var state: AppState

    private let swatches = ["#000000", "#1C1C1E", "#0A1F44", "#2B1055", "#3A0A1E", "#0B3D2E", "#FFFFFF"]

    var body: some View {
        Form {
            Section("Background") {
                ColorPicker("Color", selection: Binding(
                    get: { Color(hex: state.backgroundHex) },
                    set: { state.backgroundHex = $0.hexString }
                ), supportsOpacity: false)
                HStack(spacing: 6) {
                    ForEach(swatches, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .overlay(Circle().stroke(.secondary, lineWidth: state.backgroundHex == hex ? 2 : 0.5))
                            .frame(width: 20, height: 20)
                            .onTapGesture { state.backgroundHex = hex }
                    }
                }
                LabeledContent("Opacity \(percent(state.backgroundOpacity))") {
                    PlainSlider(value: $state.backgroundOpacity, range: 0...1)
                }
                LabeledContent("Blur \(percent(state.blur))") {
                    PlainSlider(value: $state.blur, range: 0...1)
                }
            }
            Section("Lyrics") {
                LabeledContent("Font Size \(Int(state.fontSize))") {
                    PlainSlider(value: Binding(get: { state.fontSize }, set: { state.fontSize = $0.rounded() }), range: 14...80)
                }
                LabeledContent("Offset") {
                    HStack(spacing: 4) {
                        offsetButton("−1", -1)
                        offsetButton("−0.25", -AppState.offsetStep)
                        Text(OffsetControl.format(state.offset))
                            .font(.body.monospacedDigit())
                            .frame(minWidth: 62)
                        offsetButton("+0.25", AppState.offsetStep)
                        offsetButton("+1", 1)
                        Button("Reset") { state.offset = 0 }
                            .disabled(state.offset == 0)
                    }
                    .controlSize(.small)
                }
                Text("Lyrics late → press +. Lyrics early → press −.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Highlight Words", isOn: $state.wordHighlight)
                Toggle("Romanization (Japanese, Korean, Chinese…)", isOn: $state.showRomanization)
                Toggle("Ukrainian Translation", isOn: $state.showTranslation)
                if state.showTranslation, let status = state.translationStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if state.showTranslation {
                    Toggle("Download Missing Languages Automatically", isOn: $state.autoDownloadLanguages)
                    Menu("Download Language…") {
                        ForEach(state.downloadableTranslationLanguages, id: \.minimalIdentifier) { language in
                            Button(AppState.languageName(language)) { state.downloadLanguage(language) }
                        }
                    }
                    .disabled(state.downloadableTranslationLanguages.isEmpty)
                    if !state.installedTranslationLanguages.isEmpty {
                        Text("Installed: " + state.installedTranslationLanguages.map(AppState.languageName).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if state.track != nil {
                versionsSection
            }
            Section("Window") {
                Toggle("Show Controls Only on Hover", isOn: $state.controlsOnHoverOnly)
                Toggle("Lock (Click-Through)", isOn: $state.locked)
                if state.locked {
                    Text("Unlock from the 🎤 icon in the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 600)
        .onAppear { state.refreshTranslation() }
    }

    private var versionsSection: some View {
        Section("Lyrics Version") {
            if state.candidatesLoading {
                ProgressView().controlSize(.small)
            } else if state.candidates.isEmpty {
                Text("No versions found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.candidates.prefix(20)) { record in
                    Button { state.choose(record) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(record.trackName ?? "?") — \(record.artistName ?? "?")")
                                    .lineLimit(1)
                                Text(details(record))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if record.id == state.lyricsID {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { state.loadCandidates() }
        .onChange(of: state.track) { state.loadCandidates() }
    }

    private func details(_ record: LyricsRecord) -> String {
        let kind = record.hasWords ? "Word sync"
            : record.hasSynced ? "Synced"
            : record.instrumental == true ? "Instrumental"
            : "Plain text"
        let seconds = Int(record.duration ?? 0)
        return [record.albumName, String(format: "%d:%02d", seconds / 60, seconds % 60), kind]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func offsetButton(_ title: String, _ delta: Double) -> some View {
        Button(title) { state.adjustOffset(by: delta) }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

private struct SeekBar: View {
    @ObservedObject var state: AppState
    let duration: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let position = state.scrubPosition ?? state.playbackPosition(at: context.date)
            HStack(spacing: 8) {
                timeLabel(position)
                GeometryReader { geometry in
                    let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white).frame(width: geometry.size.width * fraction)
                    }
                    .frame(height: state.scrubPosition == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                state.scrubPosition = time(at: value.location.x, width: geometry.size.width)
                            }
                            .onEnded { value in
                                state.seek(to: time(at: value.location.x, width: geometry.size.width))
                            }
                    )
                }
                .frame(height: 14)
                timeLabel(duration)
            }
        }
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1) * duration
    }

    private func timeLabel(_ seconds: Double) -> some View {
        let total = max(Int(seconds), 0)
        return Text(String(format: "%d:%02d", total / 60, total % 60))
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
    }
}

private struct PlainSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.numberOfTickMarks = 0
        slider.isContinuous = true
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        if slider.doubleValue != value { slider.doubleValue = value }
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    final class Coordinator: NSObject {
        var value: Binding<Double>
        init(value: Binding<Double>) { self.value = value }
        @objc func changed(_ sender: NSSlider) { value.wrappedValue = sender.doubleValue }
    }
}
