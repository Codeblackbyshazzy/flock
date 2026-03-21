import Foundation

struct LayoutPreset {
    let name: String
    let panes: [PaneType]
}

enum LayoutPresets {
    static let all: [LayoutPreset] = [
        LayoutPreset(name: "Single Claude", panes: [.claude]),
        LayoutPreset(name: "Claude + Shell", panes: [.claude, .shell]),
        LayoutPreset(name: "2x2 Grid", panes: [.claude, .shell, .claude, .shell]),
        LayoutPreset(name: "3-up", panes: [.claude, .claude, .shell]),
    ]
}
