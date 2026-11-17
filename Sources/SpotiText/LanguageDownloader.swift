import AppKit
import SwiftUI
import Translation

@MainActor
final class LanguageDownloader {
    private var window: NSWindow?

    func download(from source: Locale.Language, to target: Locale.Language, completion: @escaping (Bool) -> Void) {
        window?.close()
        let model = DownloadModel(source: source, target: target)
        model.onFinish = { [weak self] success in
            completion(success)
            self?.window?.close()
            self?.window = nil
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 130),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Translation Language"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: DownloadView(model: model))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class DownloadModel: ObservableObject {
    let configuration: TranslationSession.Configuration
    let title: String
    @Published var message = "Preparing download…"
    var onFinish: ((Bool) -> Void)?

    init(source: Locale.Language, target: Locale.Language) {
        configuration = TranslationSession.Configuration(source: source, target: target)
        title = "\(AppState.languageName(source)) → \(AppState.languageName(target))"
    }

    func prepare(_ session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
            onFinish?(true)
        } catch {
            message = "Download failed: \(error.localizedDescription)"
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            onFinish?(false)
        }
    }
}

private struct DownloadView: View {
    @ObservedObject var model: DownloadModel

    var body: some View {
        VStack(spacing: 12) {
            Text(model.title).font(.headline)
            ProgressView().controlSize(.small)
            Text(model.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(width: 360, height: 130)
        .translationTask(model.configuration) { session in
            await model.prepare(session)
        }
    }
}
