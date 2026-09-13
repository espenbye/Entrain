import AVFoundation

/// Renders the alarm sound: Resources/Alarm.caf, the one audio file in the app.
///
///     swift Tools/alarm.swift
///
/// AlarmKit plays a bundled file, so this is the exception to synthesizing
/// everything live. It is made to be loud rather than pleasant: full-scale
/// square-ish beeps, four to a burst, each burst a step higher, pitched
/// where hearing is most sensitive. The ring loops until it is stopped.
let rate = 44_100.0
let notes = [2093.0, 2349.0, 2637.0, 2794.0, 3136.0] // C7 D7 E7 F7 G7
let beep = 0.12, gap = 0.08, rest = 0.25
let edge = 0.004

var samples: [Float] = []
for note in notes {
    for _ in 0..<4 {
        let n = Int(beep * rate)
        for i in 0..<n {
            let t = Double(i) / rate
            // Odd harmonics under Nyquist, which is a square wave without aliasing.
            var v = 0.0
            var h = 1.0
            while note * h < rate / 2 {
                v += sin(2 * .pi * note * h * t) / h
                h += 2
            }
            let ramp = min(1, t / edge, (beep - t) / edge)
            samples.append(Float(v * ramp))
        }
        samples.append(contentsOf: repeatElement(0, count: Int(gap * rate)))
    }
    samples.append(contentsOf: repeatElement(0, count: Int(rest * rate)))
}
let peak = samples.map(abs).max()!
for i in samples.indices { samples[i] = samples[i] / peak * 0.98 }

let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
buffer.frameLength = AVAudioFrameCount(samples.count)
samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }

let url = URL(fileURLWithPath: "Resources/Alarm.caf")
try? FileManager.default.removeItem(at: url)
let file = try AVAudioFile(
    forWriting: url,
    settings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
    ]
)
try file.write(from: buffer)
print("\(samples.count) samples, \(String(format: "%.1f", Double(samples.count) / rate)) s")
