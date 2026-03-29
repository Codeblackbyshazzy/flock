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
            if let text {
                self?.owningPane?.outputParser.feed(text)
            }
        }
    }

    // Wren compression on paste (Claude panes only)
    override func paste(_ sender: Any?) {
        guard Settings.shared.wrenCompressionEnabled,
              owningPane?.paneType == .claude,
              let text = NSPasteboard.general.string(forType: .string),
              text.count >= 300 else {
            super.paste(sender as Any)
            return
        }

        WrenCompressor.shared.compress(text) { [weak self] compressed, _ in
            self?.send(txt: compressed)
        }
    }

    // Broadcast input: when typing in one pane, send to all others
    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        guard let manager = owningPane?.manager, manager.isBroadcasting else { return }
        for pane in manager.panes {
            guard let termPane = pane as? TerminalPane, termPane !== owningPane else { continue }
            termPane.terminalView.process.send(data: data)
        }
    }
}
