import Foundation
import Cocoa
import SwiftUI
import GhosttyKit

/// Controller for a popup terminal that runs a specific command and
/// auto-closes when the command exits. Anchored to a parent window.
class PopupController: BaseTerminalController {
    /// The parent window that this popup is anchored to.
    private weak var parentWindow: NSWindow?

    /// The geometry of the popup as percentages (0-100) of the parent window.
    private let popupX: UInt8
    private let popupY: UInt8
    private let popupWidth: UInt8
    private let popupHeight: UInt8

    /// Observers for parent window changes.
    private var parentObservers: [NSObjectProtocol] = []

    init(
        _ ghostty: Ghostty.App,
        parentWindow: NSWindow,
        command: String,
        x: UInt8,
        y: UInt8,
        width: UInt8,
        height: UInt8
    ) {
        self.parentWindow = parentWindow
        self.popupX = x
        self.popupY = y
        self.popupWidth = width
        self.popupHeight = height

        // Wrap the command in the user's login shell so that PATH and
        // other environment setup from profile/rc files is available.
        // Using -l (login) -i (interactive) -c (command) ensures the
        // shell loads its startup files before executing the command.
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let escapedCommand = command.replacingOccurrences(of: "'", with: "'\\''")
        let wrappedCommand = "\(shell) -lic 'exec \(escapedCommand)'"

        var config = Ghostty.SurfaceConfiguration()
        config.command = wrappedCommand
        config.commandNoWait = true

        // Initialize with an empty surface tree (we'll create the surface in windowDidLoad)
        super.init(ghostty, surfaceTree: .init())

        // Create the window programmatically
        let frame = computeFrame(in: parentWindow)
        let panel = PopupWindow(contentRect: frame)
        panel.delegate = self
        self.window = panel

        // Set up the content view
        panel.contentView = TerminalViewContainer {
            TerminalView(ghostty: ghostty, viewModel: self, delegate: self)
        }

        // Add a thin border
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.borderWidth = 1.0
            contentView.layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
        }

        // Create the terminal surface
        guard let ghostty_app = ghostty.app else { return }
        let view = Ghostty.SurfaceView(ghostty_app, baseConfig: config)
        surfaceTree = SplitTree(view: view)
        focusedSurface = view

        // Observe parent window changes
        let center = NotificationCenter.default
        parentObservers.append(center.addObserver(
            forName: NSWindow.didResizeNotification,
            object: parentWindow,
            queue: .main
        ) { [weak self] _ in
            self?.repositionToParent()
        })
        parentObservers.append(center.addObserver(
            forName: NSWindow.willCloseNotification,
            object: parentWindow,
            queue: .main
        ) { [weak self] _ in
            self?.closePopup()
        })

        // Attach the popup as a child window so macOS keeps it above
        // the parent at all times and moves it together with the parent.
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.makeKey()
        panel.makeFirstResponder(view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    deinit {
        let center = NotificationCenter.default
        for observer in parentObservers {
            center.removeObserver(observer)
        }
    }

    // MARK: - BaseTerminalController Overrides

    override func surfaceTreeDidChange(
        from: SplitTree<Ghostty.SurfaceView>,
        to: SplitTree<Ghostty.SurfaceView>
    ) {
        super.surfaceTreeDidChange(from: from, to: to)

        // When the surface tree empties (command exited), close the popup.
        // We also check that we have a window — during init the tree starts
        // empty before the window is created, and we don't want to close then.
        if to.isEmpty, window != nil {
            closePopup()
        }
    }

    override func closeSurface(
        _ node: SplitTree<Ghostty.SurfaceView>.Node,
        withConfirmation: Bool = true
    ) {
        // For popup terminals, never confirm — just close immediately.
        super.closeSurface(node, withConfirmation: false)
    }

    // MARK: - Private

    private func computeFrame(in parent: NSWindow) -> NSRect {
        let parentFrame = parent.frame
        let xOffset = parentFrame.width * CGFloat(popupX) / 100.0
        let yOffset = parentFrame.height * CGFloat(popupY) / 100.0
        let w = parentFrame.width * CGFloat(popupWidth) / 100.0
        let h = parentFrame.height * CGFloat(popupHeight) / 100.0

        return NSRect(
            x: parentFrame.origin.x + xOffset,
            y: parentFrame.origin.y + parentFrame.height - yOffset - h,
            width: w,
            height: h
        )
    }

    private func repositionToParent() {
        guard let parentWindow = parentWindow,
              let window = self.window else { return }
        let frame = computeFrame(in: parentWindow)
        window.setFrame(frame, display: true)
    }

    func closePopup() {
        // Detach from parent before closing to cleanly break the
        // child-window relationship.
        if let window = window, let parentWindow = parentWindow {
            parentWindow.removeChildWindow(window)
        }
        window?.close()

        // Clear the reference on the parent's terminal controller
        if let parentWindow = parentWindow,
           let tc = parentWindow.windowController as? TerminalController {
            tc.popupController = nil
        }
    }

    // MARK: - First Responder

    @IBAction override func closeWindow(_ sender: Any) {
        closePopup()
    }
}
