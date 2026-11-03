import AppKit
import Observation
import SwiftUI

/// The window keeps one fixed size for its whole life: resizing a transparent always-on-top
/// window paints one stale frame, so all motion happens in SwiftUI inside it.
@MainActor
final class PillPanel: NSPanel {
    static let size = CGSize(width: 460, height: 76)

    private let store: PillStore
    private var onScreen = false

    init(state: PillStore, meter: PillMeter, actions: AppActions?) {
        store = state
        super.init(contentRect: CGRect(origin: .zero, size: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        animationBehavior = .none

        let region = PillHitRegion()
        let root = PillPanelRoot(store: state, meter: meter, actions: actions, region: region)
        let host = PassthroughHostingView(rootView: root)
        host.region = region
        host.frame = CGRect(origin: .zero, size: Self.size)
        host.sizingOptions = []
        contentView = host
        observe()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        guard !onScreen else { return }
        position()
        onScreen = true
        alphaValue = 1
        orderFrontRegardless()
    }

    func hide() {
        guard onScreen else { return }
        onScreen = false
        orderOut(nil)
    }

    /// Set once per appearance so the pill stays put while the mouse moves.
    private func position() {
        let anchor = Self.focusedWindowCenter() ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        setFrameOrigin(CGPoint(x: area.midX - Self.size.width / 2, y: area.minY + 12))
    }

    /// In Cocoa screen coordinates; nil without Accessibility or a focused window.
    private static func focusedWindowCenter() -> CGPoint? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let primary = NSScreen.screens.first else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let element = window as! AXUIElement
        var origin = CGPoint.zero, size = CGSize.zero
        var position: CFTypeRef?, extent: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &extent) == .success,
              let position, let extent,
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(extent as! AXValue, .cgSize, &size) else { return nil }
        // Accessibility measures from the primary screen's top-left with y pointing down.
        return CGPoint(x: origin.x + size.width / 2, y: primary.frame.maxY - (origin.y + size.height / 2))
    }

    private func observe() {
        withObservationTracking { _ = store.state } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.apply(self.store.state)
                self.observe()
            }
        }
        apply(store.state)
    }

    private var hideTask: Task<Void, Never>?

    private func apply(_ state: PillState) {
        hideTask?.cancel()
        if state == .hidden {
            // Let the collapse animation finish before the window leaves the screen.
            hideTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        } else {
            show()
        }
        ignoresMouseEvents = !Self.isInteractive(state)
    }

    private static func isInteractive(_ state: PillState) -> Bool {
        if case .locked = state { return true }
        return false
    }
}

/// Where the pill is drawn, in the hosting view's top-left coordinates.
private final class PillHitRegion {
    var rect: CGRect = .zero
}

private struct PillPanelRoot: View {
    var store: PillStore
    var meter: PillMeter
    weak var actions: AppActions?
    let region: PillHitRegion

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if store.state != .hidden {
                PillView(store: store, meter: meter, actions: actions)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { region.rect = $0 }
                    .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 14)
        .frame(width: PillPanel.size.width, height: PillPanel.size.height)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.state == .hidden)
    }
}

/// Lets clicks outside the pill fall through to the app underneath. SwiftUI buttons aren't
/// subviews, so the test has to use the pill's drawn frame rather than the view hierarchy.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    fileprivate var region: PillHitRegion?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let topLeft = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        guard region?.rect.contains(topLeft) == true else { return nil }
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
