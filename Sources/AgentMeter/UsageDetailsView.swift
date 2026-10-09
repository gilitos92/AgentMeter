import AppKit
import SwiftUI

struct UsageDetailsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @State private var contentHeight: CGFloat?

    var body: some View {
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
        .frame(minWidth: 360, idealWidth: 360, maxWidth: .infinity)
        .frame(height: min(contentHeight ?? 500, Self.maxHeight))
        .background(MenuMaterialBackground().ignoresSafeArea())
        .background(WindowLevelSetter(alwaysOnTop: settings.usageDetailsAlwaysOnTop,
                                      onAllSpaces: settings.usageDetailsOnAllSpaces))
        .toolbar {
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
            }
        }
    }
}

/// A plain toolbar button that toggles a window option. Toolbar `Toggle`s draw
/// as filled accent-colored buttons when on; this keeps the standard toolbar
/// look and shows the state through a filled, accent-tinted symbol instead.
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
                .foregroundStyle(isOn && isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
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

/// The translucent material of the menu bar dropdown, kept active while the
/// app is in the background so a floating window keeps the same look.
private struct MenuMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Floats the hosting window above other apps' windows when enabled and, if
/// also requested, shows it on every Space and over full-screen apps.
/// SwiftUI's `windowLevel(_:)` requires macOS 15, so this configures the owning
/// NSWindow through a zero-size probe view.
struct WindowLevelSetter: NSViewRepresentable {
    let alwaysOnTop: Bool
    let onAllSpaces: Bool

    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.alwaysOnTop = alwaysOnTop
        nsView.onAllSpaces = onAllSpaces
    }

    final class ProbeView: NSView {
        static let allSpacesBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        var alwaysOnTop = false {
            didSet { applyLevel() }
        }

        var onAllSpaces = false {
            didSet { applyLevel() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyLevel()
        }

        private func applyLevel() {
            guard let window else { return }
            window.level = alwaysOnTop ? .floating : .normal
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
    }
}
