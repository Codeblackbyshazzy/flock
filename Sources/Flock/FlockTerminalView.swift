import AppKit
import SwiftTerm

class FlockTerminalView: LocalProcessTerminalView {
    weak var owningPane: TerminalPane?

    // Detect output for activity dots
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        DispatchQueue.main.async { [weak self] in
            self?.owningPane?.didReceiveOutput()
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
