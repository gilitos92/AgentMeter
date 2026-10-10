import AppKit
import SwiftUI

struct UsageDetailsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @State private var contentHeight: CGFloat?
    @State private var titleBarInset: CGFloat = 0
    @State private var isPointerInside = false
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if settings.usageDetailsCompact {
                CompactUsageView(
                    entries: store.compactEntries,
                    settings: settings,
                    isPointerInside: isPointerInside,
                    close: { dismissWindow(id: "usage-details") }
                )
            } else {
                expandedContent
            }
        }
        .modifier(UsageDetailsBackground(
            opacity: settings.usageDetailsBackgroundOpacity,
            clearGlass: settings.usageDetailsClearGlass,
            topInset: settings.usageDetailsCompact ? 0 : titleBarInset
        ))
        // The window still reserves title bar space even with the toolbar
        // hidden. Content that extends under the title bar (the compact panel,
        // and any content on glass) gives that space back so the window hugs it.
        .padding(.bottom, settings.usageDetailsCompact || UsageDetailsBackground.extendsUnderTitleBar
                 ? -titleBarInset : 0)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { titleBarInset = proxy.safeAreaInsets.top }
                    .onChange(of: proxy.safeAreaInsets.top) { _, inset in titleBarInset = inset }
            }
        }
        .background(WindowLevelSetter(alwaysOnTop: settings.usageDetailsAlwaysOnTop,
                                      onAllSpaces: settings.usageDetailsOnAllSpaces,
                                      compact: settings.usageDetailsCompact,
                                      onPointerInsideChange: { isPointerInside = $0 }))
        // The compact panel has no title bar controls; its own hover controls
        // replace the toolbar.
        .toolbar(settings.usageDetailsCompact ? .hidden : .visible, for: .windowToolbar)
        .toolbar { windowOptions }
    }

    /// The window option buttons. On macOS 26 and later they share one Liquid
    /// Glass background, like a floating toolbar.
    @ToolbarContentBuilder
    private var windowOptions: some ToolbarContent {
        if #available(macOS 26, *) {
            floatingToolbar
        } else {
            windowOptionsGroup
        }
    }

    /// The window's transparent title bar keeps the system from drawing its
    /// own toolbar glass, so the buttons carry their own glass capsule.
    @available(macOS 26, *)
    private var floatingToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 2) {
                CompactControlButton(
                    title: L("Keep on Top"),
                    symbol: settings.usageDetailsAlwaysOnTop ? "pin.fill" : "pin",
                    isOn: settings.usageDetailsAlwaysOnTop,
                    help: L("Keep this window above other windows, even when you switch apps."),
                    large: true
                ) { settings.usageDetailsAlwaysOnTop.toggle() }
                CompactControlButton(
                    title: L("Show on All Desktops"),
                    symbol: settings.usageDetailsOnAllSpaces
                        ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle",
                    isOn: settings.usageDetailsOnAllSpaces,
                    help: L("Also show this window on every desktop and over full-screen apps. Requires Keep on Top."),
                    large: true
                ) { settings.usageDetailsOnAllSpaces.toggle() }
                .disabled(!settings.usageDetailsAlwaysOnTop)
                BackgroundButton(
                    opacity: $settings.usageDetailsBackgroundOpacity,
                    clearGlass: $settings.usageDetailsClearGlass,
                    compact: true,
                    large: true
                )
                CompactControlButton(
                    title: L("Compact View"),
                    symbol: "rectangle.compress.vertical",
                    isOn: false,
                    help: L("Collapse into a small panel with each provider's limits."),
                    large: true
                ) { settings.usageDetailsCompact = true }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var windowOptionsGroup: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            WindowOptionButton(
                title: L("Keep on Top"),
                help: L("Keep this window above other windows, even when you switch apps."),
                offSymbol: "pin",
                onSymbol: "pin.fill",
                isOn: $settings.usageDetailsAlwaysOnTop
            )

            WindowOptionButton(
                title: L("Show on All Desktops"),
                help: L("Also show this window on every desktop and over full-screen apps. Requires Keep on Top."),
                offSymbol: "rectangle.on.rectangle",
                onSymbol: "rectangle.fill.on.rectangle.fill",
                isOn: $settings.usageDetailsOnAllSpaces
            )
            .disabled(!settings.usageDetailsAlwaysOnTop)

            BackgroundButton(
                opacity: $settings.usageDetailsBackgroundOpacity,
                clearGlass: $settings.usageDetailsClearGlass,
                compact: false
            )

            WindowOptionButton(
                title: L("Compact View"),
                help: L("Collapse into a small panel with each provider's limits."),
                offSymbol: "rectangle.compress.vertical",
                onSymbol: "rectangle.compress.vertical",
                isOn: $settings.usageDetailsCompact
            )
        }
    }

    private var expandedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ProviderUsageSections(store: store, settings: settings)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: UsageDetailsContentHeightKey.self, value: proxy.size.height)
                }
            }
        }
        .onPreferenceChange(UsageDetailsContentHeightKey.self) { height in
            guard height > 0, contentHeight != height else { return }
            contentHeight = height
        }
        // The window fits its content (see `windowResizability(.contentSize)`)
        // and scrolls only when the content is taller than the screen allows.
        // Wide enough for the title and all toolbar buttons without overflow.
        .frame(minWidth: 480, idealWidth: 480, maxWidth: .infinity)
        .frame(height: min(contentHeight ?? 500, Self.maxHeight))
    }
}

/// The collapsed Usage Details window: a chrome-free panel with one row per
/// limit window (e.g. 5h and weekly) for each provider. Window controls appear
/// while the pointer is over the panel, or always with VoiceOver.
private struct CompactUsageView: View {
    let entries: [CompactUsageEntry]
    @ObservedObject var settings: SettingsStore
    let isPointerInside: Bool
    let close: () -> Void
    @State private var isAdjustingOpacity = false
    @State private var labelWidth: CGFloat?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var showsControls: Bool {
        isPointerInside || isAdjustingOpacity || voiceOverEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entries) { entry in
                CompactProviderRow(entry: entry, countDirection: settings.countDirection, labelWidth: labelWidth)
            }
        }
        // Size the label column to the widest label so bars sit close to it
        // and stay aligned across rows.
        .onPreferenceChange(CompactLabelWidthKey.self) { width in
            guard width > 0, labelWidth != width else { return }
            labelWidth = width
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(minWidth: 300, alignment: .leading)
        .fixedSize()
        .overlay(alignment: .topTrailing) {
            controls
                .padding(6)
                .opacity(showsControls ? 1 : 0)
                .allowsHitTesting(showsControls)
                .animation(.easeOut(duration: 0.15), value: showsControls)
        }
        // The panel has no title bar, so it sits flush with the window edges.
        .ignoresSafeArea()
    }

    private var controls: some View {
        HStack(spacing: 2) {
            CompactControlButton(title: L("Close"), symbol: "xmark", isOn: false, action: close)
            CompactControlButton(
                title: L("Keep on Top"),
                symbol: settings.usageDetailsAlwaysOnTop ? "pin.fill" : "pin",
                isOn: settings.usageDetailsAlwaysOnTop
            ) { settings.usageDetailsAlwaysOnTop.toggle() }
            CompactControlButton(
                title: L("Show on All Desktops"),
                symbol: settings.usageDetailsOnAllSpaces
                    ? "rectangle.fill.on.rectangle.fill" : "rectangle.on.rectangle",
                isOn: settings.usageDetailsOnAllSpaces
            ) { settings.usageDetailsOnAllSpaces.toggle() }
            .disabled(!settings.usageDetailsAlwaysOnTop)
            BackgroundButton(
                opacity: $settings.usageDetailsBackgroundOpacity,
                clearGlass: $settings.usageDetailsClearGlass,
                compact: true,
                isPresented: $isAdjustingOpacity
            )
            CompactControlButton(
                title: L("Expand"),
                symbol: "rectangle.expand.vertical",
                isOn: false
            ) { settings.usageDetailsCompact = false }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
    }
}

private struct CompactControlButton: View {
    let title: String
    let symbol: String
    let isOn: Bool
    /// Tooltip; defaults to the title.
    var help: String?
    /// Larger symbols for the expanded window's floating toolbar.
    var large = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: large ? 15 : 12, weight: .semibold))
                .frame(width: large ? 30 : 20, height: large ? 28 : 20)
                .contentShape(Rectangle())
                .foregroundStyle(isOn && isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct CompactProviderRow: View {
    let entry: CompactUsageEntry
    let countDirection: CountDirection
    let labelWidth: CGFloat?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ProviderBadge(provider: entry.provider, size: 18)
            if entry.windows.isEmpty {
                summary
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entry.windows.enumerated()), id: \.offset) { _, window in
                        CompactWindowMeter(
                            providerName: entry.provider.displayName,
                            window: window,
                            countDirection: countDirection,
                            labelWidth: labelWidth
                        )
                    }
                }
            }
        }
    }

    private var summary: some View {
        let color = Color(nsColor: MenuBarTitleRenderer.nsColor(for: entry.severity))
        return HStack(spacing: 4) {
            Text(entry.summary)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
            if let symbol = Self.symbolName(for: entry.severity) {
                Image(systemName: symbol).font(.subheadline.weight(.medium)).foregroundStyle(color)
            }
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel)
    }

    private static func symbolName(for severity: MenuBarSeverity) -> String? {
        switch severity {
        case .normal: nil
        case .warning: UsageMeterSeverity.warning.symbolName
        case .critical: UsageMeterSeverity.critical.symbolName
        case .stale: "clock"
        }
    }
}

private struct CompactWindowMeter: View {
    let providerName: String
    let window: UsageWindow
    let countDirection: CountDirection
    let labelWidth: CGFloat?

    private static let barWidth: CGFloat = 80

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            meter(at: context.date)
        }
    }

    private func meter(at now: Date) -> some View {
        let severity = UsageMeterSeverity.forUsedPercent(window.usedPercent)
        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                Text(window.label)
                    .foregroundStyle(.secondary)
                if let remaining = window.shortRemainingDescription(now: now) {
                    Text(verbatim: "(\(remaining))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: CompactLabelWidthKey.self, value: proxy.size.width)
                }
            }
            .frame(width: labelWidth, alignment: .leading)
            ProgressView(value: min(100, max(0, countDirection.displayPercent(window.usedPercent))), total: 100)
                .tint(severity.color)
                .frame(width: Self.barWidth)
            HStack(spacing: 3) {
                Text(countDirection.percentLabel(window.usedPercent, menuBar: true))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(severity.color)
                // Severity is never shown by color alone.
                if let symbol = severity.symbolName {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(severity.color)
                }
            }
            .frame(width: 60, alignment: .trailing)
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L("%@, %@"), providerName, window.label))
        .accessibilityValue(accessibilityValue(severity: severity, now: now))
    }

    private func accessibilityValue(severity: UsageMeterSeverity, now: Date) -> String {
        var value = countDirection.accessibilityPercentPhrase(window.usedPercent)
        if let reset = window.resetDescription(style: .relative, now: now) {
            value = "\(value), \(reset)"
        }
        guard let qualifier = severity.qualifier else { return value }
        return MenuBarAccessibilitySummary.appendQualifier(value, qualifier)
    }
}

private struct CompactLabelWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A plain toolbar button that toggles a window option. Toolbar `Toggle`s draw
/// as filled accent-colored buttons when on; this keeps the standard toolbar
/// look and shows the state through a filled symbol in the primary color instead.
private struct WindowOptionButton: View {
    let title: String
    let help: String
    let offSymbol: String
    let onSymbol: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: isOn ? onSymbol : offSymbol)
                .foregroundStyle(isOn && isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .help(help)
        .accessibilityValue(isOn ? L("On") : L("Off"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension UsageDetailsView {
    /// Leaves room for the title bar and some margin on the current screen.
    static var maxHeight: CGFloat {
        max(200, (NSScreen.main?.visibleFrame.height ?? 820) - 120)
    }
}

private struct UsageDetailsContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Opens the window background options: the glass variant on macOS 26 and
/// later, the background opacity before that. The toolbar and the compact
/// panel's hover controls each show one.
private struct BackgroundButton: View {
    @Binding var opacity: Double
    @Binding var clearGlass: Bool
    let compact: Bool
    var large = false
    var isPresented: Binding<Bool>?
    @State private var localIsPresented = false

    private var presented: Binding<Bool> {
        isPresented ?? $localIsPresented
    }

    private var title: String {
        UsageDetailsBackground.extendsUnderTitleBar ? L("Glass") : L("Opacity")
    }

    private var helpText: String {
        UsageDetailsBackground.extendsUnderTitleBar
            ? L("Choose regular or clear glass for the window background.")
            : L("Adjust how see-through the window background is.")
    }

    var body: some View {
        Group {
            if compact {
                CompactControlButton(
                    title: title,
                    symbol: "circle.lefthalf.filled",
                    isOn: false,
                    help: large ? helpText : nil,
                    large: large
                ) {
                    presented.wrappedValue.toggle()
                }
            } else {
                Button {
                    presented.wrappedValue.toggle()
                } label: {
                    Label(title, systemImage: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                }
                .help(helpText)
            }
        }
        .popover(isPresented: presented, arrowEdge: .bottom) {
            if #available(macOS 26, *) {
                GlassPicker(clearGlass: $clearGlass)
            } else {
                OpacitySlider(opacity: $opacity)
            }
        }
    }
}

private struct GlassPicker: View {
    @Binding var clearGlass: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Glass"), selection: $clearGlass) {
                Text(L("Regular")).tag(false)
                Text(L("Clear")).tag(true)
            }
            .pickerStyle(.segmented)
            Text(L("Clear glass dims what is behind it to keep text readable."))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 240)
    }
}

private struct OpacitySlider: View {
    @Binding var opacity: Double

    private var percent: String {
        "\(Int((opacity * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Background opacity")).font(.callout.weight(.medium))
                Spacer()
                Text(percent).font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: $opacity, in: 0...1, step: 0.05)
                .accessibilityLabel(L("Background opacity"))
                .accessibilityValue(percent)
        }
        .padding(12)
        .frame(width: 220)
    }
}

/// The window background. On macOS 26 and later the content sits inside
/// Liquid Glass, so the system keeps text legible over anything behind the
/// window: regular glass adapts its tint and the content's light or dark
/// appearance; clear glass gets a dimming layer and light content, as Apple's
/// guidelines require. Earlier systems use the menu material.
private struct UsageDetailsBackground: ViewModifier {
    let opacity: Double
    let clearGlass: Bool
    /// Title bar height the content must clear once it extends under it.
    let topInset: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    static var extendsUnderTitleBar: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            // The glass spans the whole window, title bar included, so the
            // content extends under it and pads itself back down.
            content
                .padding(.top, topInset)
                .environment(\.colorScheme, clearGlass ? .dark : colorScheme)
                .glassEffect(clearGlass ? .clear : .regular, in: ConcentricRectangle())
                .background {
                    if clearGlass {
                        ConcentricRectangle().fill(.black.opacity(0.35))
                    }
                }
                .ignoresSafeArea()
        } else {
            content.background(MenuMaterialBackground(opacity: opacity).ignoresSafeArea())
        }
    }
}

/// The translucent material of the menu bar dropdown, kept active while the
/// app is in the background so a floating window keeps the same look. Its
/// opacity is adjustable; content drawn on top stays fully opaque.
private struct MenuMaterialBackground: NSViewRepresentable {
    let opacity: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.alphaValue = opacity
    }
}

/// Floats the hosting window above other apps' windows when enabled and, if
/// also requested, shows it on every Space and over full-screen apps.
/// SwiftUI's `windowLevel(_:)` requires macOS 15, so this configures the owning
/// NSWindow through a zero-size probe view.
struct WindowLevelSetter: NSViewRepresentable {
    let alwaysOnTop: Bool
    let onAllSpaces: Bool
    var compact = false
    /// Reports whether the pointer is anywhere over the window. SwiftUI's
    /// `onHover` lost the pointer over the compact panel's top strip, which
    /// hid its controls as soon as the pointer reached them.
    var onPointerInsideChange: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onPointerInsideChange = onPointerInsideChange
        nsView.alwaysOnTop = alwaysOnTop
        nsView.onAllSpaces = onAllSpaces
        nsView.compact = compact
    }

    final class ProbeView: NSView {
        static let allSpacesBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        var alwaysOnTop = false {
            didSet { applyLevel() }
        }

        var onAllSpaces = false {
            didSet { applyLevel() }
        }

        var compact = false {
            didSet { applyLevel() }
        }
        private var fullSizeContentBeforeCompact: Bool?
        private var dragMonitor: Any?
        private var mouseDownLocation: NSPoint?
        private var pointerTrackingArea: NSTrackingArea?
        private weak var pointerTrackingView: NSView?
        var onPointerInsideChange: (Bool) -> Void = { _ in }

        deinit {
            if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
            if let pointerTrackingArea { pointerTrackingView?.removeTrackingArea(pointerTrackingArea) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyLevel()
            installPointerTracking()
        }

        /// Tracks the whole window frame, title bar included, independent of
        /// which view is under the pointer.
        private func installPointerTracking() {
            if let pointerTrackingArea {
                pointerTrackingView?.removeTrackingArea(pointerTrackingArea)
                self.pointerTrackingArea = nil
            }
            guard let window, let frameView = window.contentView?.superview else { return }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            frameView.addTrackingArea(area)
            pointerTrackingArea = area
            pointerTrackingView = frameView
            let inside = window.frame.contains(NSEvent.mouseLocation)
            DispatchQueue.main.async { [weak self] in self?.onPointerInsideChange(inside) }
        }

        override func mouseEntered(with event: NSEvent) {
            onPointerInsideChange(true)
        }

        override func mouseExited(with event: NSEvent) {
            onPointerInsideChange(false)
        }

        private func applyLevel() {
            guard let window else { return }
            window.level = alwaysOnTop ? .floating : .normal
            // Let the window's material show through the title bar, and let a
            // faded material show what is behind the window.
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            applyCompactChrome(to: window)
            orderTitlebar(of: window)
            // Over full-screen apps the window must also float, so all-Spaces
            // behavior only applies together with always-on-top.
            if alwaysOnTop && onAllSpaces {
                // canJoinAllSpaces and moveToActiveSpace are mutually exclusive.
                window.collectionBehavior.remove(.moveToActiveSpace)
                window.collectionBehavior.formUnion(Self.allSpacesBehavior)
            } else {
                window.collectionBehavior.subtract(Self.allSpacesBehavior)
            }
        }

        /// SwiftUI content swallows clicks, so isMovableByWindowBackground only
        /// works over the reserved title bar strip, and an inactive window's
        /// first click never reaches SwiftUI gestures. While compact, any drag
        /// inside the window moves it, even when another app is active.
        private func updateDragMonitor() {
            if compact, dragMonitor == nil {
                dragMonitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.leftMouseDown, .leftMouseDragged]
                ) { [weak self] event in
                    guard let self, let window, event.window === window else { return event }
                    if event.type == .leftMouseDown {
                        mouseDownLocation = event.locationInWindow
                        return event
                    }
                    // Small pointer jitter during a click must not start a drag,
                    // or the click never reaches the panel's buttons.
                    if let start = mouseDownLocation {
                        let distance = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
                        guard distance >= 3 else { return event }
                    }
                    window.performDrag(with: event)
                    return nil
                }
            } else if !compact, let monitor = dragMonitor {
                NSEvent.removeMonitor(monitor)
                dragMonitor = nil
            }
        }

        /// The full-size SwiftUI content can end up ordered above the title
        /// bar, where its material hides the title, window buttons and toolbar.
        /// Keep the title bar in front of the content in the expanded window,
        /// and behind it in the compact panel, which draws its own controls.
        private func orderTitlebar(of window: NSWindow) {
            let compact = compact
            DispatchQueue.main.async {
                guard let container = window.standardWindowButton(.closeButton)?.superview?.superview,
                      let contentView = window.contentView,
                      let frameView = container.superview,
                      contentView.superview === frameView,
                      let containerIndex = frameView.subviews.firstIndex(of: container),
                      let contentIndex = frameView.subviews.firstIndex(of: contentView) else { return }
                if compact, containerIndex > contentIndex {
                    frameView.addSubview(container, positioned: .below, relativeTo: contentView)
                } else if !compact, containerIndex < contentIndex {
                    frameView.addSubview(container, positioned: .above, relativeTo: contentView)
                }
            }
        }

        /// The compact panel has no visible title bar: content fills the whole
        /// window, the window buttons are hidden, and it drags by its background.
        private func applyCompactChrome(to window: NSWindow) {
            window.titleVisibility = compact ? .hidden : .visible
            window.isMovableByWindowBackground = compact
            updateDragMonitor()
            for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = compact
            }
            if compact {
                if fullSizeContentBeforeCompact == nil {
                    fullSizeContentBeforeCompact = window.styleMask.contains(.fullSizeContentView)
                }
                window.styleMask.insert(.fullSizeContentView)
            } else if let wasFullSize = fullSizeContentBeforeCompact {
                if !wasFullSize { window.styleMask.remove(.fullSizeContentView) }
                fullSizeContentBeforeCompact = nil
            }
        }
    }
}
