import AppKit
import SwiftTerm

class FlockTerminalView: LocalProcessTerminalView {
    weak var owningPane: TerminalPane?

    // Detect output for activity dots + agent state parsing + compression analytics
    private var utf8Remainder = Data()
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        let count = slice.count
        // Copy bytes NOW -- the backing buffer may be recycled before main runs
        let data = utf8Remainder + Data(slice)
        utf8Remainder = Data()

        // Handle incomplete UTF-8 sequences at the end of the chunk
        // by trimming trailing bytes that form an incomplete multi-byte character
        var validEnd = data.count
        if validEnd > 0 {
            // Walk back up to 3 bytes to find a valid UTF-8 boundary
            let checkLen = min(validEnd, 4)
            for i in 1...checkLen {
                let byte = data[data.index(data.endIndex, offsetBy: -i)]
                if byte & 0x80 == 0 { break }           // ASCII - boundary is fine
                if byte & 0xC0 == 0xC0 {                // Start of multi-byte sequence
                    let seqLen = byte < 0xE0 ? 2 : byte < 0xF0 ? 3 : 4
                    if i < seqLen {
                        // Incomplete sequence at end - save remainder
                        validEnd = data.count - i
                        utf8Remainder = data.suffix(i)
                    }
                    break
                }
            }
        }

        let validData = data.prefix(validEnd)
        let text = String(data: validData, encoding: .utf8)
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
        let snapshot = manager.panes
        for pane in snapshot {
            guard let termPane = pane as? TerminalPane,
                  termPane !== owningPane,
                  termPane.terminalView.process.running else { continue }
            termPane.terminalView.process.send(data: data)
        }
    }
}
