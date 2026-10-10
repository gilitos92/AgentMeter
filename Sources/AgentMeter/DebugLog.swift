import Foundation

/// Opt-in stderr tracing for development only (`ALLOWANCEBAR_DEBUG=1`).
/// Never logs credentials; callers must pass only structural information.
enum DebugLog {
    nonisolated private static let enabled =
        ProcessInfo.processInfo.environment["ALLOWANCEBAR_DEBUG"] != nil

    nonisolated static func write(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("[AllowanceBar] \(message())\n".utf8))
    }
}
