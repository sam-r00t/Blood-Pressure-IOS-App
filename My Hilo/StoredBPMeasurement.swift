import Foundation
import SwiftData
import CryptoKit

@Model
final class StoredBPMeasurement {
    var sequence: Int
    var timestamp: Date
    var systolic: Int
    var diastolic: Int
    var heartRate: Int?
    var id: String
    var rawFramesJSON: String?
    var calculationLogs: String?
    var payloadHash: String?

    var cuffLogs: String?
    var podLogs: String?
    var isCalibration: Bool = false

    init(sequence: Int, timestamp: Date, systolic: Int, diastolic: Int, heartRate: Int? = nil, rawFramesJSON: String? = nil, calculationLogs: String? = nil, isCalibration: Bool = false) {
        self.sequence = sequence
        self.timestamp = timestamp
        self.systolic = systolic
        self.diastolic = diastolic
        self.heartRate = heartRate
        self.rawFramesJSON = rawFramesJSON
        self.calculationLogs = calculationLogs
        self.isCalibration = isCalibration
        self.id = UUID().uuidString

        if let data = rawFramesJSON?.data(using: .utf8) {
            self.payloadHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }
}
