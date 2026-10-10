import Foundation

public enum StatusPaths {
    public static let appBundleIdentifier = "com.ggv.AllowanceBar"

    public static var snapshotFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AllowanceBar/status.json", isDirectory: false)
    }
}
