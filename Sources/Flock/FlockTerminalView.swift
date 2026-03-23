import AppKit
import SwiftTerm

class FlockTerminalView: LocalProcessTerminalView {
    weak var owningPane: TerminalPane?

    // Detect output for activity dots + agent state parsing + compression analytics
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        let count = slice.count
        // Copy bytes NOW -- the backing buffer may be recycled before main runs
        let bytes = Array(slice)
        let text = String(bytes: bytes, encoding: .utf8)
        DispatchQueue.main.async { [weak self] in
            self?.owningPane?.didReceiveOutput(byteCount: count)
            self?.owningPane?.compressor.feed(bytes[...])
            if let text {
                self?.owningPane?.outputParser.feed(text)
            }
        }
    }

    // Broadcast input: when typing in one pane, send to all others
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        guard let manager = owningPane?.manager, manager.isBroadcasting else { return }
        for pane in manager.panes where pane !== owningPane {
            pane.terminalView.process.send(data: data)
        }
    }
}
