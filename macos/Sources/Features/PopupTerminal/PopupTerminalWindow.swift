import Cocoa

class PopupTerminalWindow: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        self.identifier = .init(rawValue: "com.mitchellh.ghostty.popupTerminal")
        self.setAccessibilitySubrole(.floatingWindow)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        // Use normal level so the popup only appears above the parent
        // Ghostty window, not above all windows in the OS.
        self.level = .normal
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
    }
}
