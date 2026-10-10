import Foundation

/// Window usage severity from percent thresholds (shared by menu bar tinting,
/// progress bar color, and accessibility qualifiers).
enum UsageMeterSeverity: Equatable {
    case normal, warning, critical

    nonisolated static func forUsedPercent(_ percent: Double) -> Self {
        switch percent {
        case ..<60: return .normal
        case ..<85: return .warning
        default: return .critical
        }
    }

    nonisolated var qualifier: String? {
        switch self {
        case .normal: return nil
        case .warning: return L("high usage")
        case .critical: return L("nearly used up")
        }
    }

    nonisolated var symbolName: String? {
        switch self {
        case .normal: return nil
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

import SwiftUI

extension UsageMeterSeverity {
    /// Progress bar and percent tint.
    var color: Color {
        switch self {
        case .normal: return .primary
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

/// Horizontal usage bar. Drawn with SwiftUI shapes rather than a tinted
/// `ProgressView`: AppKit resolves the tint once, so `.primary` stayed black in
/// dark mode and colors went stale after an appearance change.
struct UsageMeterBar: View {
    /// 0...100.
    let percent: Double
    let severity: UsageMeterSeverity

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(severity.color)
                    .frame(width: proxy.size.width * min(1, max(0, percent / 100)))
            }
        }
        .frame(height: 6)
        // Matches the spacing the system progress bar used to reserve.
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}
