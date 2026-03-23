import AppKit
import SwiftTerm

class FlockTerminalView: LocalProcessTerminalView {
    weak var owningPane: TerminalPane?

    /// Set true before programmatic sends so the compressor isn't armed by them.
    var isProgrammaticSend = false

    // Detect output for activity dots + agent state parsing + compression analytics
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        let count = slice.count
        // Copy bytes NOW -- the backing buffer may be recycled before main runs
        let bytes = Array(slice)
        let text = String(bytes: bytes, encoding: .utf8)
        DispatchQueue.main.async { [weak self] in
            self?.owningPane?.didReceiveOutput(byteCount: count)
            // Feed compressor (parallel analytics -- does not modify data)
            self?.owningPane?.compressor.feed(bytes[...])
            if let text {
                self?.owningPane?.outputParser.feed(text)
            }
        }
    }

    // Broadcast input: when typing in one pane, send to all others
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        // Only arm compressor on real user keystrokes, not programmatic sendText
        if !isProgrammaticSend {
            owningPane?.compressor.markReady()
        }
        guard let manager = owningPane?.manager, manager.isBroadcasting else { return }
        for pane in manager.panes where pane !== owningPane {
            pane.terminalView.process.send(data: data)
        }
    }
}
