import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow
    @State private var menuScreenVisibleHeight: CGFloat?
    @State private var providerContentHeight: CGFloat?
    @State private var providerContentBottom: CGFloat = 0

    private let tipJarURL = URL(string: "https://www.buymeacoffee.com/gilitos92")!


    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            usageView
        }
        .padding(14)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                MenuWindowScreenReader(contentSize: proxy.size) { height in
                    DispatchQueue.main.async {
                        guard menuScreenVisibleHeight != height else { return }
                        menuScreenVisibleHeight = height
                    }
                }
            }
        }
    }

    private var usageView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ProviderUsageSections(store: store, settings: settings)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ProviderContentHeightKey.self,
                            value: proxy.size.height
                        )
                        .preference(
                            key: ProviderContentBottomKey.self,
                            value: proxy.frame(in: .named("providerViewport")).maxY
                        )
                    }
                }
            }
            .frame(height: providerViewportHeight, alignment: .top)
            .coordinateSpace(name: "providerViewport")
            .onPreferenceChange(ProviderContentHeightKey.self) { height in
                guard providerContentHeight != height else { return }
                providerContentHeight = height
            }
            .onPreferenceChange(ProviderContentBottomKey.self) { bottom in
                providerContentBottom = bottom
            }
            .overlay(alignment: .bottom) {
                if providerContentBottom > providerViewportHeight + 1 {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask {
                            LinearGradient(colors: [.clear, .black],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .frame(height: 36)
                        .overlay(alignment: .bottom) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 4)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            Divider()
            footer
        }
    }

    private var providerViewportHeight: CGFloat {
        // Keep the footer reachable while leaving a little room for the
        // menu's outer padding and title-bar/menu-bar overlap. The fallback
        // covers the first layout pass, before the popup has an owning window.
        let screenHeight = menuScreenVisibleHeight ?? 820
        let maxHeight = max(1, min(680, screenHeight - 150))
        guard let providerContentHeight else { return 1 }
        return min(providerContentHeight, maxHeight)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let refreshed = store.lastRefreshed {
                    Text(L("Updated \(refreshed.formatted(date: .omitted, time: .shortened))"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.refresh(forceRefresh: true)
                } label: {
                    Label(L("Refresh"), systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .help(L("Refresh"))
                .accessibilityLabel(L("Refresh"))
            }
            HStack {
                Button {
                    openUsageDetails()
                } label: {
                    Text(L("Usage Details"))
                }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .keyboardShortcut("d", modifiers: [.command])
                .help(L("Usage Details"))
                .accessibilityLabel(L("Usage Details"))
                SettingsLink {
                    Text(L("Settings…"))
                }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .help(L("Settings…"))
                .accessibilityLabel(L("Settings…"))
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                    Self.closeMenuBarWindow()
                })
                Spacer()
                Button(L("Check for Updates…")) {
                    Self.closeMenuBarWindow()
                    Updater.shared.checkForUpdates()
                }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                .help(L("Check for Updates…"))
                .accessibilityLabel(L("Check for Updates…"))
                Spacer()
                Link(destination: tipJarURL) {
                    Text(L("Support ♥"))
                }
                .font(.callout.weight(.medium))
                .help(L("Support ♥"))
                .accessibilityLabel(L("Support ♥"))
                Spacer()
                Button(L("Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.medium))
                    .help(L("Quit"))
                    .accessibilityLabel(L("Quit"))
            }
        }
    }

    private func openUsageDetails() {
        Self.closeMenuBarWindow()
        openWindow(id: "usage-details")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// MenuBarExtra's window doesn't auto-dismiss when another window opens;
    /// close it explicitly so Settings doesn't appear behind the dropdown.
    private static func closeMenuBarWindow() {
        for window in NSApp.windows where window.className.contains("MenuBarExtraWindow") {
            window.close()
        }
    }
}

private struct ProviderContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ProviderContentBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Reports the visible height of the display that owns MenuBarExtra's popup.
/// The popup window is created after the initial SwiftUI layout, so this is a
/// zero-size probe rather than a GeometryReader that could participate in a
/// layout feedback loop.
private struct MenuWindowScreenReader: NSViewRepresentable {
    let contentSize: CGSize
    let onVisibleHeightChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScreenProbeView {
        ScreenProbeView(onVisibleHeightChange: onVisibleHeightChange)
    }

    func updateNSView(_ nsView: ScreenProbeView, context: Context) {
        nsView.onVisibleHeightChange = onVisibleHeightChange
        nsView.contentSize = contentSize
        nsView.scheduleContentResize()
    }

    final class ScreenProbeView: NSView {
        var onVisibleHeightChange: (CGFloat) -> Void
        private weak var observedWindow: NSWindow?
        private var lastReportedHeight: CGFloat?
        var contentSize: CGSize = .zero
        private var resizeScheduled = false

        // MenuBarExtra can retain its first layout's native window height even
        // after SwiftUI has measured and contracted the provider list.
        func scheduleContentResize() {
            guard !resizeScheduled else { return }
            resizeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resizeScheduled = false
                guard let window = self.window,
                      window.className.contains("MenuBarExtraWindow"),
                      self.contentSize.width > 0, self.contentSize.height > 0 else { return }
                let size = NSSize(width: ceil(self.contentSize.width),
                                  height: ceil(self.contentSize.height))
                let current = window.contentRect(forFrameRect: window.frame).size
                guard abs(current.height - size.height) > 1 ||
                      abs(current.width - size.width) > 1 else { return }
                let top = window.frame.maxY
                window.contentMinSize = size
                window.contentMaxSize = size
                window.setContentSize(size)
                window.setFrameOrigin(NSPoint(x: window.frame.minX,
                                              y: top - window.frame.height))
            }
        }

        init(onVisibleHeightChange: @escaping (CGFloat) -> Void) {
            self.onVisibleHeightChange = onVisibleHeightChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if observedWindow !== window {
                removeObservers()
                observedWindow = window
                if let window {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(windowScreenChanged),
                        name: NSWindow.didChangeScreenNotification,
                        object: window
                    )
                }
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowScreenChanged),
                    name: NSApplication.didChangeScreenParametersNotification,
                    object: nil
                )
            }
            reportVisibleHeight()
            scheduleContentResize()
        }

        deinit {
            removeObservers()
        }

        @objc private func windowScreenChanged() {
            reportVisibleHeight()
        }

        func reportVisibleHeight() {
            guard let height = window?.screen?.visibleFrame.height else { return }
            guard lastReportedHeight != height else { return }
            lastReportedHeight = height
            onVisibleHeightChange(height)
        }

        private func removeObservers() {
            NotificationCenter.default.removeObserver(self)
            observedWindow = nil
        }
    }
}
