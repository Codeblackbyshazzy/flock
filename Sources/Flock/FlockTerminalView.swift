import AppKit
import SwiftTerm

class FlockTerminalView: LocalProcessTerminalView {
    weak var owningPane: TerminalPane?

    // Detect output for activity dots + cost tracking
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        let count = slice.count
        DispatchQueue.main.async { [weak self] in
            guard let self, let pane = self.owningPane else { return }
            pane.didReceiveOutput(byteCount: count)
            if pane.type == .claude {
                CostTracker.shared.processOutput(slice, for: pane)
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
