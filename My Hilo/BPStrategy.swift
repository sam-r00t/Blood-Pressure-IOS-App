import Foundation

protocol BPComputationStrategy {
    var sourceOfTruth: String { get }
    func fetchLatestDetailed(limit: Int) async throws -> [DetailedBPResult]
}

struct DetailedBPResult {
    let measurement: BPMeasurement
    let logs: String
    let rawFramesJSON: String?
    let deviceTimestamp: Date?
}

struct LocalComputedBPStrategy: BPComputationStrategy {
    let recorder: IncomingFrameRecorder
    let model: LocalBPModel

    var sourceOfTruth: String { "Local AI Based Algorithm" }

    func fetchLatestDetailed(limit: Int) async throws -> [DetailedBPResult] {
        let url = recorder.url
        let result = try LocalBPComputer.computeDetailed(fromIncomingFramesJSONL: url, model: model, windowSeconds: 90.0)
        if let result { return [result] }
        return []
    }
}

struct LocalBPModel: Codable {
    let name: String
    let featureOrder: [String]
    let sbpIntercept: Double
    let sbpCoeff: [Double]
    let dbpIntercept: Double
    let dbpCoeff: [Double]
    let clipSBP: [Double]?
    let clipDBP: [Double]?

    static var defaultResearchBaselineV1: LocalBPModel {
        LocalBPModel(
            name: "research_baseline_v1",
            featureOrder: [
                "hr_bpm",
                "amplitude",
                "rise_time_s",
                "decay_time_s",
                "width50_s",
                "auc",
                "upstroke_slope",
                "downstroke_slope",
                "notch_delay_s",
            ],
            sbpIntercept: 110.0,
            sbpCoeff: [0.20, 8.0, 4.0, 2.0, -3.0, 3.5, 1.5, -0.8, 6.0],
            dbpIntercept: 70.0,
            dbpCoeff: [0.12, 4.0, 1.5, 1.0, -2.0, 1.8, 0.8, -0.5, 3.0],
            clipSBP: [80.0, 200.0],
            clipDBP: [40.0, 130.0]
        )
    }

    static func loadFromBundleOrDefault() -> LocalBPModel {

        if let url = Bundle.main.url(forResource: "model", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(BundleModelJSON.self, from: data) {
            return decoded.toLocalBPModel()
        }
        return .defaultResearchBaselineV1
    }

    private struct BundleModelJSON: Codable {
        struct Head: Codable { let intercept: Double; let coeff: [Double] }
        let name: String
        let feature_order: [String]
        let sbp: Head
        let dbp: Head
        let clip: Clip?
        struct Clip: Codable { let sbp: [Double]?; let dbp: [Double]? }

        func toLocalBPModel() -> LocalBPModel {
            LocalBPModel(
                name: name,
                featureOrder: feature_order,
                sbpIntercept: sbp.intercept,
                sbpCoeff: sbp.coeff,
                dbpIntercept: dbp.intercept,
                dbpCoeff: dbp.coeff,
                clipSBP: clip?.sbp,
                clipDBP: clip?.dbp
            )
        }
    }
}

enum LocalBPComputer {
    private static let targetCharacteristic = "A6B41002-003D-4E65-9208-08F4DB958863"
    private static let fs: Double = 25.0

    static var minSignalQuality: Double = 0.35

    struct ComputationResult {
        let timestamp: Date
        let systolic: Int
        let diastolic: Int
        let heartRate: Int?
        let debug: [String: Double]
    }

    static func computeDetailed(fromIncomingFramesJSONL url: URL, model: LocalBPModel, windowSeconds: Double, gated: Bool = true) throws -> DetailedBPResult? {
        let frames = try readIncomingFrames(url: url)
        let rawContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return try computeDetailed(frames: frames, model: model, windowSeconds: windowSeconds, rawContent: rawContent, gated: gated)
    }

    static func computeDetailed(fromRawWaveformBuffer buffer: Data, model: LocalBPModel) throws -> DetailedBPResult? {
        var frames: [IncomingFrame] = []
        var offset = 0
        let sessionStartTime = Date()

        while offset < buffer.count {
            let limit = min(244, buffer.count - offset)
            let chunk = buffer.subdata(in: offset..<(offset + limit))

            let priorSamples = frames.reduce(0) { $0 + $1.samplesInt16LE.count }
            let simulatedTime = sessionStartTime.addingTimeInterval(Double(priorSamples) / Self.fs)

            if let frame = parseRawFrame(chunk, receivedAt: simulatedTime) {
                frames.append(frame)
            }
            offset += 244
        }

        return try computeDetailed(frames: frames, model: model, windowSeconds: 90.0, rawContent: "Collector Raw Buffer (\(buffer.count) bytes)")
    }

    private static func computeDetailed(frames: [IncomingFrame], model: LocalBPModel, windowSeconds: Double, rawContent: String, gated: Bool = true) throws -> DetailedBPResult? {
        var logs = "========================================================\n"
        logs += "Local AI BP Computation Execution Log\n"
        logs += "Generated: \(Date().formatted(date: .long, time: .standard))\n"
        logs += "========================================================\n"

        func log(_ msg: String) {
            print(msg)
            logs += msg + "\n"
        }

        log("\n[COMPUTE][START] Target: \(targetCharacteristic) Model: \(model.name)")

        let rawSessionFrames = isolateLastSession(frames, gapThreshold: 5.0)
        guard !rawSessionFrames.isEmpty else {
            log("[COMPUTE][SKIP] No valid data session found.")
            return nil
        }

        let sessionFrames = dedupeConsecutive(rawSessionFrames)
        if sessionFrames.count != rawSessionFrames.count {
            log("[COMPUTE][DEDUP] Removed \(rawSessionFrames.count - sessionFrames.count) duplicate frame(s) (\(rawSessionFrames.count) -> \(sessionFrames.count))")
        }

        let framesWithDeviceTime = sessionFrames.compactMap { $0.deviceTimestamp }
        let startTime: Date
        let endTime: Date
        let usedDeviceTime: Bool

        if let firstDT = framesWithDeviceTime.first, let lastDT = framesWithDeviceTime.last, firstDT != lastDT {

            startTime = firstDT
            endTime = lastDT
            usedDeviceTime = true
            log("[COMPUTE][CONFIG] True Device Payload Timestamps Available (Delta: \(endTime.timeIntervalSince(startTime))s)")
        } else {

            startTime = sessionFrames.first?.timestamp ?? Date()
            endTime = sessionFrames.last?.timestamp ?? Date()
            usedDeviceTime = false
            log("[COMPUTE][CONFIG] Falling back to iOS insertion timestamps")
        }

        log("[COMPUTE][TIME] Data Start: \(startTime.formatted(date: .omitted, time: .standard))")
        log("[COMPUTE][TIME] Data End:   \(endTime.formatted(date: .omitted, time: .standard))")

        let duration = endTime.timeIntervalSince(startTime)
        let totalSamples = sessionFrames.reduce(0) { $0 + $1.samplesInt16LE.count }

        let fs = Self.fs

        log("[COMPUTE][SESSION] Duration: \(String(format: "%.2f", duration))s, Samples: \(totalSamples), fs: \(String(format: "%.1f", fs)) Hz (fixed)")

        var all: [Double] = []
        all.reserveCapacity(totalSamples)
        for f in sessionFrames {
            all.append(contentsOf: f.samplesInt16LE.map { Double($0) })
        }

        log("[COMPUTE] Raw Sample Glimpse (first 10): \(all.prefix(10).map { String(format: "%.0f", $0) }.joined(separator: ", "))")

        log("[COMPUTE][STEP 2] Preprocessing: Removing DC bias, normalizing, and applying bandpass...")
        let processed = preprocess(all, fs: fs)
        log("[COMPUTE] Processed Glimpse (first 10): \(processed.prefix(10).map { String(format: "%.4f", $0) }.joined(separator: ", "))")

        let (quality, autocorrHR) = signalQuality(processed, fs: fs)
        log("[COMPUTE][QUALITY] cardiac periodicity=\(String(format: "%.3f", quality)) autocorr-HR=\(String(format: "%.0f", autocorrHR)) bpm (gate \(Self.minSignalQuality))")
        if gated && quality < Self.minSignalQuality {
            log("[COMPUTE][FAIL] Signal quality \(String(format: "%.3f", quality)) below gate — likely noise or Pod not on skin. No reading produced.")
            return nil
        }
        if !gated && quality < Self.minSignalQuality {
            log("[COMPUTE][RESEARCH] Low signal quality \(String(format: "%.3f", quality)) — producing UNVALIDATED research estimate (needs more research; not a real BP).")
        }

        log("[COMPUTE][STEP 3] Peak Detection: Searching for systolic peaks (dist > \(Int(fs * 60.0 / 150)) samples)...")
        let peaks = findPeaks(processed, fs: fs)
        log("[COMPUTE] Peak indices detected (\(peaks.count)): \(peaks.prefix(15).map { String($0) }.joined(separator: ", "))\(peaks.count > 15 ? "..." : "")")

        log("[COMPUTE][STEP 4] Feature Extraction: Calculating beat morphology features...")
        let beats = extractBeatFeatures(processed, peaks: peaks, fs: fs)
        if let firstBeat = beats.first {
            log("[COMPUTE] First Beat Features: amp=\(String(format: "%.2f", firstBeat.amplitude)), rise=\(String(format: "%.3f", firstBeat.riseTime)), decay=\(String(format: "%.3f", firstBeat.decayTime)), hr=\(String(format: "%.1f", firstBeat.hrBpm ?? 0))")
        }

        log("[COMPUTE][STEP 5] Quality Filter: Validation check...")
        let kept = qualityFilter(beats)
        log("[COMPUTE] Passed: \(kept.count), Rejected: \(beats.count - kept.count)")

        guard !kept.isEmpty else {
            log("[COMPUTE][FAIL] No valid beats remaining.")
            return nil
        }

        log("[COMPUTE][STEP 6] Aggregation: Building prediction vector...")
        let features = aggregateFeatures(kept, order: model.featureOrder)
        for (k, v) in features.sorted(by: { $0.key < $1.key }) {
            log("  - \(k.padding(toLength: 16, withPad: " ", startingAt: 0)): \(String(format: "%.4f", v))")
        }

        log("[COMPUTE][STEP 7] Prediction: Linear regression...")
        let (sbp, dbp) = predictBP(features: features, model: model)

        log("[COMPUTE][SUCCESS] Est. SBP: \(Int(round(sbp))) mmHg, DBP: \(Int(round(dbp))) mmHg, HR: \(Int(round(features["hr_bpm"] ?? 0.0))) bpm\n")
        log("========================================================")
        log("Computation routine finished successfully.")

        let hr = Int(round(autocorrHR > 0 ? autocorrHR : (features["hr_bpm"] ?? 0.0)))
        let measurement = BPMeasurement(
            id: UUID().uuidString,
            timestamp: endTime,
            systolic: Int(round(sbp)),
            diastolic: Int(round(dbp)),
            heartRate: hr > 0 ? hr : nil,

            source: "local-uncalibrated:\(model.name)"
        )

        return DetailedBPResult(
            measurement: measurement,
            logs: logs,
            rawFramesJSON: rawContent,
            deviceTimestamp: usedDeviceTime ? endTime : nil
        )
    }

    private static func parseRawFrame(_ data: Data, receivedAt: Date) -> IncomingFrame? {
        let bytes = [UInt8](data)

        guard bytes.count == 244 else { return nil }

        let dt = AktiiaTimestampDecoder.decode(from: data, characteristicUUID: targetCharacteristic)

        var samples: [Int] = []
        if (bytes[0] & 0x80) == 0 {
            var i = 4
            while i + 2 < bytes.count {
                samples.append(Int(bytes[i]) << 8 | Int(bytes[i + 1]))
                i += 3
            }
        }

        return IncomingFrame(
            timestamp: receivedAt,
            deviceTimestamp: dt,
            characteristicUUID: targetCharacteristic,
            samplesInt16LE: samples
        )
    }

    private static func isolateLastSession(_ frames: [IncomingFrame], gapThreshold: TimeInterval) -> [IncomingFrame] {
        guard !frames.isEmpty else { return [] }

        let wf = frames
            .filter { $0.characteristicUUID.uppercased() == targetCharacteristic && $0.samplesInt16LE.count > 0 }
            .sorted { $0.timestamp < $1.timestamp }
        guard !wf.isEmpty else { return [] }

        var sessions: [[IncomingFrame]] = []
        var currentSession: [IncomingFrame] = [wf[0]]

        for i in 1..<wf.count {
            let prev = wf[i-1]
            let curr = wf[i]
            if curr.timestamp.timeIntervalSince(prev.timestamp) > gapThreshold {

                sessions.append(currentSession)
                currentSession = [curr]
            } else {
                currentSession.append(curr)
            }
        }
        sessions.append(currentSession)

        return sessions.last ?? []
    }

    private static func dedupeConsecutive(_ frames: [IncomingFrame]) -> [IncomingFrame] {
        var out: [IncomingFrame] = []
        out.reserveCapacity(frames.count)
        var lastChar: String? = nil
        var lastSamples: [Int]? = nil
        for f in frames {
            if f.characteristicUUID == lastChar && f.samplesInt16LE == lastSamples {
                continue
            }
            out.append(f)
            lastChar = f.characteristicUUID
            lastSamples = f.samplesInt16LE
        }
        return out
    }

    private struct IncomingFrameLine: Codable {
        let timestamp: String
        let deviceTimestamp: String?
        let characteristicUUID: String
        let decoded244: Decoded244?

        struct Decoded244: Codable {
            let samplesInt16LE: [Int]
        }
    }

    private struct IncomingFrame {
        let timestamp: Date
        let deviceTimestamp: Date?
        let characteristicUUID: String
        let samplesInt16LE: [Int]
    }

    private static func readIncomingFrames(url: URL) throws -> [IncomingFrame] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]

        var out: [IncomingFrame] = []
        out.reserveCapacity(2048)

        for line in text.split(separator: "\n") {
            guard !line.isEmpty else { continue }
            guard let ld = line.data(using: .utf8) else { continue }
            guard let parsed = try? JSONDecoder().decode(IncomingFrameLine.self, from: ld) else { continue }

            guard let insertionDt = iso.date(from: parsed.timestamp) ?? ISO8601DateFormatter().date(from: parsed.timestamp) else { continue }

            var deviceDt: Date? = nil
            if let deviceTimeStr = parsed.deviceTimestamp,
               let parsedDeviceDt = iso.date(from: deviceTimeStr) ?? ISO8601DateFormatter().date(from: deviceTimeStr) {
                deviceDt = parsedDeviceDt
            }

            let samples = parsed.decoded244?.samplesInt16LE ?? []
            out.append(IncomingFrame(
                timestamp: insertionDt,
                deviceTimestamp: deviceDt,
                characteristicUUID: parsed.characteristicUUID,
                samplesInt16LE: samples
            ))
        }
        return out
    }

    private static func signalQuality(_ x: [Double], fs: Double) -> (Double, Double) {
        let win = Int(fs * 8.0)
        guard x.count >= win, win > 2 else { return (0, 0) }
        let minLag = max(1, Int(fs * 60.0 / 180.0))
        let maxLag = min(win - 1, Int(fs * 60.0 / 40.0))
        guard maxLag > minLag else { return (0, 0) }

        var qualities: [Double] = []
        var hrs: [Double] = []
        var start = 0
        while start + win <= x.count {
            let seg = Array(x[start..<(start + win)])
            let mean = seg.reduce(0, +) / Double(win)
            let c = seg.map { $0 - mean }
            let denom = c.reduce(0) { $0 + $1 * $1 }
            if denom > 0 {
                var best = 0.0
                var bestLag = 0
                for lag in minLag...maxLag {
                    var s = 0.0
                    for i in 0..<(win - lag) { s += c[i] * c[i + lag] }
                    let r = s / denom
                    if r > best { best = r; bestLag = lag }
                }
                qualities.append(best)
                if bestLag > 0 { hrs.append(60.0 / (Double(bestLag) / fs)) }
            }
            start += win
        }
        guard !qualities.isEmpty else { return (0, 0) }
        let medQ = qualities.sorted()[qualities.count / 2]
        let medHR = hrs.isEmpty ? 0 : hrs.sorted()[hrs.count / 2]
        return (medQ, medHR)
    }

    private static func movingAverage(_ x: [Double], window: Int) -> [Double] {
        let w = max(1, window)
        guard w > 1, !x.isEmpty else { return x }
        let n = x.count
        let half = w / 2
        var out = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            var s = 0.0
            for k in 0..<w {
                let idx = i + k - half
                if idx >= 0 && idx < n {
                    s += x[idx]
                }
            }
            out[i] = s / Double(w)
        }
        return out
    }

    private static func preprocess(_ xIn: [Double], fs: Double) -> [Double] {
        guard !xIn.isEmpty else { return xIn }
        let mean = xIn.reduce(0, +) / Double(xIn.count)
        var x = xIn.map { $0 - mean }
        let m = x.map { abs($0) }.max() ?? 0
        if m > 0 { x = x.map { $0 / m } }

        let baselineWin = max(3, Int(round(fs * 2.0)))
        let baseline = movingAverage(x, window: baselineWin)
        let xHP = zip(x, baseline).map { $0 - $1 }

        let smoothWin = max(3, Int(round(fs * 0.12)))
        var xBP = movingAverage(xHP, window: smoothWin)
        let m2 = xBP.map { abs($0) }.max() ?? 0
        if m2 > 0 { xBP = xBP.map { $0 / m2 } }
        return xBP
    }

    private static func percentile(_ x: [Double], p: Double) -> Double {
        guard !x.isEmpty else { return 0.0 }
        let sorted = x.sorted()
        let pos = (p / 100.0) * Double(sorted.count - 1)
        let lo = Int(floor(pos))
        let hi = Int(ceil(pos))
        if lo == hi { return sorted[lo] }
        let t = pos - Double(lo)
        return sorted[lo] * (1.0 - t) + sorted[hi] * t
    }

    private static func findPeaks(_ x: [Double], fs: Double, minBPM: Double = 45, maxBPM: Double = 150) -> [Int] {
        guard x.count >= 3 else { return [] }
        let minDist = max(1, Int(fs * 60.0 / maxBPM))
        let thr = max(0.12, percentile(x, p: 80))
        let promWin = max(2, Int(round(fs * 0.32)))
        let widthMin = max(2, Int(round(fs * 0.08)))
        let widthMax = max(widthMin + 1, Int(round(fs * 0.80)))

        var peaks: [Int] = []
        peaks.reserveCapacity(256)

        for i in 1..<(x.count - 1) {
            if x[i] < thr { continue }
            if !(x[i] >= x[i - 1] && x[i] >= x[i + 1]) { continue }

            let l0 = max(0, i - promWin)
            let r0 = min(x.count, i + promWin + 1)

            let leftMin = (i > l0) ? (x[l0..<i].min() ?? x[i]) : x[i]
            let rightMin = (i + 1 < r0) ? (x[(i + 1)..<r0].min() ?? x[i]) : x[i]
            let prom = x[i] - max(leftMin, rightMin)
            if prom < 0.08 { continue }

            let half = x[i] - (prom * 0.5)
            var l = i
            while l > l0 && x[l] > half { l -= 1 }
            var r = i
            while (r + 1) < r0 && x[r] > half { r += 1 }
            let width = r - l
            if width < widthMin || width > widthMax { continue }

            peaks.append(i)
        }

        guard !peaks.isEmpty else { return [] }

        var filtered: [Int] = [peaks[0]]
        for p in peaks.dropFirst() {
            let prev = filtered[filtered.count - 1]
            if p - prev < minDist {
                if x[p] > x[prev] { filtered[filtered.count - 1] = p }
            } else {
                filtered.append(p)
            }
        }
        return filtered
    }

    private static func localMinIndex(_ x: [Double], a: Int, b: Int) -> Int {
        if b <= a { return a }
        var minIdx = a
        var minVal = x[a]
        for i in a..<b {
            if x[i] < minVal {
                minVal = x[i]
                minIdx = i
            }
        }
        return minIdx
    }

    private static func halfWidthSeconds(_ x: [Double], start: Int, peak: Int, end: Int, fs: Double) -> Double? {
        let amp = x[peak] - x[start]
        if amp <= 0 { return nil }
        let half = x[start] + amp * 0.5

        var left: Int? = nil
        for i in start...peak {
            if x[i] >= half { left = i; break }
        }
        var right: Int? = nil
        if peak < end {
            for i in peak..<end {
                if x[i] <= half { right = i; break }
            }
        }
        guard let l = left, let r = right, r > l else { return nil }
        return Double(r - l) / fs
    }

    private static func notchProxy(_ x: [Double], peak: Int, end: Int) -> Int? {
        let span = max(1, end - peak)
        let stop = peak + Int(0.6 * Double(span))
        if stop <= peak + 2 { return nil }
        if stop > x.count { return nil }
        let seg = Array(x[peak..<stop])
        if seg.count < 5 { return nil }

        var minIdx = 2
        var minVal = seg[2]
        for i in 2..<seg.count {
            if seg[i] < minVal {
                minVal = seg[i]
                minIdx = i
            }
        }
        return peak + minIdx
    }

    private struct Beat {
        let hrBpm: Double?
        let amplitude: Double
        let riseTime: Double
        let decayTime: Double
        let width50: Double?
        let auc: Double
        let upSlope: Double
        let downSlope: Double
        let notchDelay: Double?
    }

    private static func extractBeatFeatures(_ x: [Double], peaks: [Int], fs: Double) -> [Beat] {
        guard peaks.count >= 3 else { return [] }
        var beats: [Beat] = []
        beats.reserveCapacity(peaks.count)

        for i in 1..<(peaks.count - 1) {
            let prevP = peaks[i - 1]
            let p = peaks[i]
            let nextP = peaks[i + 1]

            let start = localMinIndex(x, a: prevP, b: p)
            let end = localMinIndex(x, a: p, b: nextP)
            if !(start < p && p < end) { continue }

            let amp = x[p] - x[start]
            if amp <= 0 { continue }

            let rrS = Double(nextP - p) / fs
            let hr = (rrS > 0) ? (60.0 / rrS) : nil
            let riseS = Double(p - start) / fs
            let decayS = Double(end - p) / fs

            let baseline = x[start]
            var auc = 0.0
            if end > start {
                for j in start..<(end) {
                    let y0 = x[j] - baseline
                    let y1 = x[j + 1] - baseline
                    auc += (y0 + y1) * 0.5 * (1.0 / fs)
                }
            }

            let width50 = halfWidthSeconds(x, start: start, peak: p, end: end, fs: fs)
            let upSlope = (x[p] - x[start]) / max(1.0, Double(p - start)) * fs
            let downSlope = (x[end] - x[p]) / max(1.0, Double(end - p)) * fs

            let nidx = notchProxy(x, peak: p, end: end)
            let notchDelay = nidx.map { Double($0 - p) / fs }

            beats.append(
                Beat(
                    hrBpm: hr,
                    amplitude: amp,
                    riseTime: riseS,
                    decayTime: decayS,
                    width50: width50,
                    auc: auc,
                    upSlope: upSlope,
                    downSlope: downSlope,
                    notchDelay: notchDelay
                )
            )
        }
        return beats
    }

    private static func qualityFilter(_ beats: [Beat]) -> [Beat] {
        guard !beats.isEmpty else { return [] }
        let amps = beats.map { $0.amplitude }.sorted()
        let ampP10 = percentile(amps, p: 10)
        let ampP95 = percentile(amps, p: 95)

        var kept: [Beat] = []
        kept.reserveCapacity(beats.count)

        for b in beats {
            guard let h = b.hrBpm, (45.0...140.0).contains(h) else { continue }
            if !(ampP10...ampP95).contains(b.amplitude) { continue }
            if !(0.08...1.2).contains(b.riseTime) { continue }
            guard let w = b.width50, (0.08...1.2).contains(w) else { continue }
            if b.upSlope <= 0 { continue }
            if b.downSlope >= 0 { continue }
            kept.append(b)
        }
        return kept
    }

    private static func aggregateFeatures(_ beats: [Beat], order: [String]) -> [String: Double] {
        func mean(_ xs: [Double]) -> Double {
            guard !xs.isEmpty else { return 0.0 }
            return xs.reduce(0, +) / Double(xs.count)
        }

        var feats: [String: Double] = [:]
        for k in order {
            switch k {
            case "hr_bpm":
                feats[k] = mean(beats.compactMap { $0.hrBpm })
            case "amplitude":
                feats[k] = mean(beats.map { $0.amplitude })
            case "rise_time_s":
                feats[k] = mean(beats.map { $0.riseTime })
            case "decay_time_s":
                feats[k] = mean(beats.map { $0.decayTime })
            case "width50_s":
                feats[k] = mean(beats.compactMap { $0.width50 })
            case "auc":
                feats[k] = mean(beats.map { $0.auc })
            case "upstroke_slope":
                feats[k] = mean(beats.map { $0.upSlope })
            case "downstroke_slope":
                feats[k] = mean(beats.map { $0.downSlope })
            case "notch_delay_s":
                feats[k] = mean(beats.compactMap { $0.notchDelay })
            default:
                feats[k] = 0.0
            }
        }
        return feats
    }

    private static func predictBP(features: [String: Double], model: LocalBPModel) -> (Double, Double) {
        let x = model.featureOrder.map { features[$0] ?? 0.0 }
        func dot(_ a: [Double], _ b: [Double]) -> Double {
            let n = min(a.count, b.count)
            var s = 0.0
            for i in 0..<n { s += a[i] * b[i] }
            return s
        }

        var sbp = model.sbpIntercept + dot(model.sbpCoeff, x)
        var dbp = model.dbpIntercept + dot(model.dbpCoeff, x)

        if let c = model.clipSBP, c.count == 2 {
            sbp = min(max(sbp, c[0]), c[1])
        }
        if let c = model.clipDBP, c.count == 2 {
            dbp = min(max(dbp, c[0]), c[1])
        }
        return (sbp, dbp)
    }
}
