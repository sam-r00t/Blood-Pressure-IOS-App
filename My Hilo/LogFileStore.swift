import Foundation

final class LogFileStore {
    private let fileURL: URL
    private let lock = NSLock()

    init(fileName: String = "ble_capture.log") {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        fileURL = documents.appendingPathComponent(fileName)
        ensureFileExists()
    }

    var url: URL {
        fileURL
    }

    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }

        guard let data = text.data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            print("[BLE][LOGGER][ERROR] Failed to append log file: \(error)")
        }
    }

    func tailLines(_ maxLines: Int) -> String {
        lock.lock()
        defer { lock.unlock() }

        guard maxLines > 0 else { return "" }
        guard let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return ""
        }

        let lines = content.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return "" }

        let start = max(0, lines.count - maxLines)
        return lines[start...].joined(separator: "\n")
    }

    private func ensureFileExists() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        applyProtectionAttributes()
    }

    private func applyProtectionAttributes() {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = fileURL
        try? protectedURL.setResourceValues(values)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: fileURL.path
        )
    }
}
