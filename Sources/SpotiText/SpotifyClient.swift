import AppKit

enum PlayerState: Equatable {
    case notRunning
    case permissionDenied
    case stopped
    case paused
    case playing
}

struct TrackInfo: Equatable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let duration: Double
}

struct SpotifySnapshot {
    var state: PlayerState
    var track: TrackInfo?
    var position: Double
}

@MainActor
final class SpotifyClient {
    static let bundleID = "com.spotify.client"

    private let script: NSAppleScript? = {
        let source = """
        tell application id "com.spotify.client"
            set s to player state as string
            if s is "stopped" then return {"stopped"}
            set t to current track
            return {s, id of t, name of t, artist of t, album of t, duration of t, player position}
        end tell
        """
        let script = NSAppleScript(source: source)
        script?.compileAndReturnError(nil)
        return script
    }()

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    enum Command: String {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    func send(_ command: Command) {
        guard isRunning else { return }
        NSAppleScript(source: "tell application id \"\(Self.bundleID)\" to \(command.rawValue)")?
            .executeAndReturnError(nil)
    }

    func seek(to seconds: Double) {
        guard isRunning else { return }
        let value = String(format: "%.2f", max(seconds, 0))
        NSAppleScript(source: "tell application id \"\(Self.bundleID)\" to set player position to \(value)")?
            .executeAndReturnError(nil)
    }

    func fetch() -> SpotifySnapshot {
        guard isRunning, let script else {
            return SpotifySnapshot(state: .notRunning, track: nil, position: 0)
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == -1744 {
                return SpotifySnapshot(state: .permissionDenied, track: nil, position: 0)
            }
            return SpotifySnapshot(state: .stopped, track: nil, position: 0)
        }

        guard result.numberOfItems >= 1 else {
            return SpotifySnapshot(state: .stopped, track: nil, position: 0)
        }

        let stateString = result.atIndex(1)?.stringValue ?? "stopped"
        guard stateString != "stopped", result.numberOfItems >= 7 else {
            return SpotifySnapshot(state: .stopped, track: nil, position: 0)
        }

        let track = TrackInfo(
            id: result.atIndex(2)?.stringValue ?? "",
            name: result.atIndex(3)?.stringValue ?? "",
            artist: result.atIndex(4)?.stringValue ?? "",
            album: result.atIndex(5)?.stringValue ?? "",
            duration: Double(result.atIndex(6)?.int32Value ?? 0) / 1000
        )
        let position = result.atIndex(7)?.doubleValue ?? 0

        return SpotifySnapshot(
            state: stateString == "playing" ? .playing : .paused,
            track: track,
            position: position
        )
    }
}
