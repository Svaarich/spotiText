import AppKit
import SwiftUI

@MainActor
final class WindowBridge {
    weak var window: NSWindow?
    var minimumSize = NSSize(width: 420, height: 200)

    private var startMouse: NSPoint?
    private var startFrame: NSRect = .zero

    func move() {
        guard let window, let delta = delta(for: window) else { return }
        window.setFrameOrigin(NSPoint(x: startFrame.minX + delta.x, y: startFrame.minY + delta.y))
    }

    func resize() {
        guard let window, let delta = delta(for: window) else { return }
        let width = max(minimumSize.width, startFrame.width + delta.x)
        let height = max(minimumSize.height, startFrame.height - delta.y)
        window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height),
                        display: true)
    }

    func end() {
        startMouse = nil
    }

    private func delta(for window: NSWindow) -> NSPoint? {
        let mouse = NSEvent.mouseLocation
        guard let start = startMouse else {
            startMouse = mouse
            startFrame = window.frame
            return nil
        }
        return NSPoint(x: mouse.x - start.x, y: mouse.y - start.y)
    }
}

struct BlurView: NSViewRepresentable {
    var intensity: Double
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.mask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.alphaValue = intensity
    }

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X",
                      Int((color.redComponent * 255).rounded()),
                      Int((color.greenComponent * 255).rounded()),
                      Int((color.blueComponent * 255).rounded()))
    }
}
