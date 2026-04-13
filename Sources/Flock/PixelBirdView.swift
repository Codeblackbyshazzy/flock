import AppKit

/// A tiny pixel-art bird that flaps between two frames, ported from the marketing site.
/// Each frame is a set of (x, y) coordinates on a 7x3 grid drawn as filled squares.
class PixelBirdView: NSView {

    private static let frame0: [(Int, Int)] = [
        (0, 0), (6, 0),
        (1, 1), (5, 1),
        (2, 2), (3, 2), (4, 2),
    ]
    private static let frame1: [(Int, Int)] = [
        (2, 0), (3, 0), (4, 0),
        (1, 1), (5, 1),
        (0, 2), (6, 2),
    ]

    private let pixelSize: CGFloat = 4
    private var currentFrame: Int = 0
    private var flapTimer: Timer?
    private var flapInterval: TimeInterval = 0.4

    // Hover speed-up
    private var hoverSpeedUpEnd: Date?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: 7 * pixelSize, height: 3 * pixelSize)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        startFlapping()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { flapTimer?.invalidate() }

    func startFlapping() {
        flapTimer?.invalidate()
        flapTimer = Timer.scheduledTimer(withTimeInterval: flapInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.currentFrame = 1 - self.currentFrame
            self.needsDisplay = true

            // Ease back from hover speed-up
            if let end = self.hoverSpeedUpEnd, Date() > end {
                self.hoverSpeedUpEnd = nil
                self.flapInterval = 0.4
                self.flapTimer?.invalidate()
                self.startFlapping()
            }
        }
    }

    /// Briefly speed up flapping (called on hover).
    func speedUp() {
        guard hoverSpeedUpEnd == nil else { return }
        flapInterval = 0.2
        hoverSpeedUpEnd = Date().addingTimeInterval(1.0)
        flapTimer?.invalidate()
        startFlapping()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let pixels = currentFrame == 0 ? Self.frame0 : Self.frame1
        ctx.setFillColor(Theme.textPrimary.cgColor)
        for (px, py) in pixels {
            ctx.fill(CGRect(
                x: CGFloat(px) * pixelSize,
                y: CGFloat(py) * pixelSize,
                width: pixelSize,
                height: pixelSize
            ))
        }
    }
}
