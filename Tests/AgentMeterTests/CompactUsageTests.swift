import XCTest
@testable import AgentMeter

final class CompactUsageTests: XCTestCase {
    @MainActor
    func testCompactEntriesListEveryVisibleProviderRegardlessOfMenuBarStyle() async throws {
        let suite = "CompactUsageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.menuBarStyle = .icon
        let store = UsageStore(settings: settings, providers: [
            CompactProvider(id: "compact-a", usedPercent: 20),
            CompactProvider(id: "compact-b", usedPercent: 70),
        ])

        let deadline = Date().addingTimeInterval(3)
        while store.compactEntries.contains(where: { $0.summary == "…" }) {
            guard Date() < deadline else { return XCTFail("providers did not finish loading") }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertTrue(store.menuBarEntries.isEmpty)
        let entries = store.compactEntries
        XCTAssertEqual(entries.map(\.id), ["compact-a", "compact-b"])
        XCTAssertEqual(entries.map(\.summary), ["20%", "70%"])
        XCTAssertEqual(entries.map(\.severity), [.normal, .warning])
        XCTAssertTrue(entries[1].accessibilityLabel.contains("Compact provider"))
    }

    @MainActor
    func testCompactSettingDefaultsOffAndPersists() {
        let suite = "CompactUsageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.usageDetailsCompact)
        settings.usageDetailsCompact = true
        XCTAssertTrue(SettingsStore(defaults: defaults).usageDetailsCompact)
    }
}

private struct CompactProvider: UsageProvider {
    let id: String
    let usedPercent: Double
    var displayName: String { "Compact provider" }
    var shortCode: String { "C" }
    var isDetected: Bool { true }
    func fetch() async throws -> ProviderUsage {
        ProviderUsage(planName: "Test", windows: [
            UsageWindow(label: "Weekly limit", usedPercent: usedPercent,
                        resetsAt: Date().addingTimeInterval(86400))
        ], asOf: Date())
    }
}
