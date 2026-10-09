import AppKit
import SwiftUI

struct UsageDetailsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ProviderUsageSections(store: store, settings: settings)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 360, minHeight: 500)
        .background(WindowLevelSetter(alwaysOnTop: settings.usageDetailsAlwaysOnTop,
                                      onAllSpaces: settings.usageDetailsOnAllSpaces))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $settings.usageDetailsAlwaysOnTop) {
                    Label(L("Keep on Top"),
                          systemImage: settings.usageDetailsAlwaysOnTop ? "pin.fill" : "pin")
                }
                .help(L("Keep this window above other windows, even when you switch apps."))

                Toggle(isOn: $settings.usageDetailsOnAllSpaces) {
                    Label(L("Show on All Desktops"), systemImage: "rectangle.on.rectangle")
                }
                .disabled(!settings.usageDetailsAlwaysOnTop)
                .help(L("Also show this window on every desktop and over full-screen apps. Requires Keep on Top."))
            }
        }
    }
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
