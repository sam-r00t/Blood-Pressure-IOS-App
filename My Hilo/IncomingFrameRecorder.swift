import Foundation

final class IncomingFrameRecorder {
    private let lock = NSLock()
    private let fileURL: URL
    private let isoFormatter: ISO8601DateFormatter

    init(fileName: String = "ble_incoming_frames.jsonl") {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        fileURL = documents.appendingPathComponent(fileName)
        isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        ensureFileExists()
    }

    var url: URL {
        fileURL
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
        ensureFileExists()
    }

    func record(frame: RawBLEFrame) {
        lock.lock()
        defer { lock.unlock() }

        var entry: [String: Any] = [
            "timestamp": isoFormatter.string(from: frame.timestamp),
            "peripheralId": frame.peripheralID.uuidString,
            "serviceUUID": frame.serviceUUID,
            "characteristicUUID": frame.characteristicUUID,
            "length": frame.payload.count,
            "hex": RawDataLogger.hexString(frame.payload),
            "base64": frame.payload.base64EncodedString()
        ]
        if let dt = frame.deviceTimestamp {
            entry["deviceTimestamp"] = isoFormatter.string(from: dt)
        }
        if let decoded = decode244Waveform(frame: frame) {
            entry["decoded244"] = decoded
        }

        guard JSONSerialization.isValidJSONObject(entry),
              let data = try? JSONSerialization.data(withJSONObject: entry),
              let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }

        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            if let newline = "\n".data(using: .utf8) {
                try handle.write(contentsOf: newline)
            }
        } catch {
            print("[BLE][RX_DUMP][ERROR] \(error)")
        }
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

    private func decode244Waveform(frame: RawBLEFrame) -> [String: Any]? {
        guard frame.payload.count == 244 else { return nil }
        guard frame.characteristicUUID.caseInsensitiveCompare("A6B41002-003D-4E65-9208-08F4DB958863") == .orderedSame else {
            return nil
        }

        let bytes = [UInt8](frame.payload)
        guard bytes.count == 244 else { return nil }

        let header = Array(bytes.prefix(4))
        var samples: [Int] = []
        if (bytes[0] & 0x80) == 0 {
            samples.reserveCapacity(80)
            var i = 4
            while i + 2 < bytes.count {
                samples.append(Int(bytes[i]) << 8 | Int(bytes[i + 1]))
                i += 3
            }
        }

        return [
            "headerHex": RawDataLogger.hexString(Data(header)),
            "frameIndex": Int(header[1]),
            "packetType": Int(header[0]),
            "isBurstStart": (bytes[0] & 0x80) != 0,
            "sampleCount": samples.count,
            "samplesInt16LE": samples
        ]
    }
}
