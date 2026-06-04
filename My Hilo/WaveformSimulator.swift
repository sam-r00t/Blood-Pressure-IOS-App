import Foundation
import CoreBluetooth

#if DEBUG

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    mutating func nextGaussian() -> Double {
        let u1 = nextUnit()
        let u2 = nextUnit()
        let r = u1 <= 0 ? 1e-12 : u1
        return (-2.0 * log(r)).squareRoot() * cos(2.0 * Double.pi * u2)
    }
}

struct PPGBeatSynthesizer {
    var fs: Double = 25.0

    var nominalHRBpm: Double = 58.0
    var hrv: Double = 0.04
    var muSys: Double = 0.34
    var sigSys: Double = 0.085
    var muDic: Double = 0.68
    var sigDic: Double = 0.11
    var wDic: Double = 0.28
    var amplitude: Double = 8000.0
    var noiseStd: Double = 11000.0

    private func cycle(_ phase: Double) -> Double {
        let sys = exp(-0.5 * pow((phase - muSys) / sigSys, 2))
        let dic = wDic * exp(-0.5 * pow((phase - muDic) / sigDic, 2))
        return sys + dic
    }

    func makeSamples(count: Int, rng: inout SeededGenerator) -> [Int16] {
        guard count > 0 else { return [] }
        let rrS = 60.0 / nominalHRBpm
        var clean = [Double](repeating: 0, count: count)

        var beatStart = 0.0
        var beatRR = rrS * (1.0 + hrv * rng.nextGaussian())
        for i in 0..<count {
            let t = Double(i) / fs
            while t - beatStart >= beatRR {
                beatStart += beatRR
                beatRR = rrS * (1.0 + hrv * rng.nextGaussian())
            }
            clean[i] = cycle((t - beatStart) / beatRR)
        }

        let mean = clean.reduce(0, +) / Double(count)
        for i in 0..<count { clean[i] -= mean }
        let maxAbs = clean.map { abs($0) }.max() ?? 0
        if maxAbs > 0 { for i in 0..<count { clean[i] /= maxAbs } }

        var out = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let v = clean[i] * amplitude + noiseStd * rng.nextGaussian()
            out[i] = Int16(clamping: Int(v.rounded()))
        }
        return out
    }
}

enum FrameEncoder {
    static let samplesPerFrame = 80
    static let frameSize = 244

    static func encode(packetType: UInt8, frameIndex: UInt8, samples: [Int16]) -> Data {
        precondition(samples.count == samplesPerFrame, "frame must carry exactly 80 samples")
        var bytes = [UInt8]()
        bytes.reserveCapacity(frameSize)

        bytes.append(contentsOf: [packetType, frameIndex, 0xF1, 0x00])
        for s in samples {
            let u = UInt16(bitPattern: s)
            bytes.append(UInt8((u >> 8) & 0xFF))
            bytes.append(UInt8(u & 0xFF))
            bytes.append(0x00)
        }
        return Data(bytes)
    }
}

struct SimulatedWaveformSource {
    var synthesizer = PPGBeatSynthesizer()
    var seed: UInt64 = 0xA6B4_1002_0000_0001
    var burstLength = 37

    private func sampleStream(frameCount: Int) -> [Int16] {
        var rng = SeededGenerator(seed: seed)
        return synthesizer.makeSamples(count: frameCount * FrameEncoder.samplesPerFrame, rng: &rng)
    }

    private func packetType(forFrame f: Int) -> UInt8 {

        0x02
    }

    func makeContinuousBuffer(frameCount: Int) -> Data {
        let samples = sampleStream(frameCount: frameCount)
        var data = Data(capacity: frameCount * FrameEncoder.frameSize)
        var frameIndex: UInt8 = 0
        for f in 0..<frameCount {
            let lo = f * FrameEncoder.samplesPerFrame
            let chunk = Array(samples[lo..<(lo + FrameEncoder.samplesPerFrame)])
            data.append(FrameEncoder.encode(packetType: packetType(forFrame: f), frameIndex: frameIndex, samples: chunk))
            frameIndex = frameIndex &+ 1
        }
        return data
    }

    func makeFrames(frameCount: Int, peripheralID: UUID, sessionStart: Date) -> [RawBLEFrame] {
        let samples = sampleStream(frameCount: frameCount)
        let perFrame = Double(FrameEncoder.samplesPerFrame) / synthesizer.fs
        var frames: [RawBLEFrame] = []
        frames.reserveCapacity(frameCount)
        var frameIndex: UInt8 = 0
        for f in 0..<frameCount {
            let lo = f * FrameEncoder.samplesPerFrame
            let chunk = Array(samples[lo..<(lo + FrameEncoder.samplesPerFrame)])
            let payload = FrameEncoder.encode(packetType: packetType(forFrame: f), frameIndex: frameIndex, samples: chunk)
            frames.append(RawBLEFrame(
                peripheralID: peripheralID,
                serviceUUID: HiloBLEProtocol.primaryServiceUUID,
                characteristicUUID: HiloBLEProtocol.primaryDataCharacteristicUUID,
                timestamp: sessionStart.addingTimeInterval(Double(f) * perFrame),
                deviceTimestamp: nil,
                payload: payload,
                characteristicProperties: []
            ))
            frameIndex = frameIndex &+ 1
        }
        return frames
    }
}

enum WaveformSimulatorValidation {
    @discardableResult
    static func run(frameCount: Int = 50, model: LocalBPModel = .defaultResearchBaselineV1) -> DetailedBPResult? {
        let source = SimulatedWaveformSource()
        let buffer = source.makeContinuousBuffer(frameCount: frameCount)
        let result = try? LocalBPComputer.computeDetailed(fromRawWaveformBuffer: buffer, model: model)
        if let m = result?.measurement {
            print("[SIM][VALIDATE] frames=\(frameCount) bytes=\(buffer.count) -> "
                  + "SBP=\(m.systolic) DBP=\(m.diastolic) HR=\(m.heartRate.map(String.init) ?? "nil") "
                  + "(expect ~144/88, HR ~78-82)")
        } else {
            print("[SIM][VALIDATE] pipeline returned nil — no measurement")
        }
        return result
    }
}

#endif
