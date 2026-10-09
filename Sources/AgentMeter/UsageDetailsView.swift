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
        .background(WindowLevelSetter(alwaysOnTop: settings.usageDetailsAlwaysOnTop))
    }
}

/// Floats the hosting window above other apps' windows when enabled.
/// SwiftUI's `windowLevel(_:)` requires macOS 15, so this sets the level on the
/// owning NSWindow through a zero-size probe view.
struct WindowLevelSetter: NSViewRepresentable {
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.alwaysOnTop = alwaysOnTop
    }

    final class ProbeView: NSView {
        var alwaysOnTop = false {
            didSet { applyLevel() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyLevel()
        }

        private func applyLevel() {
            window?.level = alwaysOnTop ? .floating : .normal
        }
    }
}
