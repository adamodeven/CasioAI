import Foundation

/// Watch audio arrives as 16kHz mono PCM16 (see WatchProtocol.AudioFrameHeader);
/// OpenAI Realtime's `pcm16` format is 24kHz mono PCM16. Rather than pull in
/// AVAudioConverter for a fixed, known-simple integer-ish ratio (16k -> 24k
/// is exactly 2:3), a small linear-interpolation resampler keeps this
/// dependency-free and cheap enough to run inline on each incoming chunk.
enum AudioResampling {

    static func resample(pcm16 input: Data, fromHz: Double, toHz: Double) -> Data {
        guard fromHz != toHz, input.count >= 2 else { return input }

        let sampleCount = input.count / 2
        guard sampleCount > 1 else { return input }

        var samples = [Int16](repeating: 0, count: sampleCount)
        _ = samples.withUnsafeMutableBytes { dest in
            input.copyBytes(to: dest, count: sampleCount * 2)
        }

        let ratio = toHz / fromHz
        let outputCount = max(1, Int(Double(sampleCount) * ratio))
        var output = [Int16](repeating: 0, count: outputCount)

        for i in 0..<outputCount {
            let srcPos = Double(i) / ratio
            let srcIndex = Int(srcPos)
            let frac = srcPos - Double(srcIndex)

            let a = samples[min(srcIndex, sampleCount - 1)]
            let b = samples[min(srcIndex + 1, sampleCount - 1)]
            output[i] = Int16(Double(a) + (Double(b) - Double(a)) * frac)
        }

        return output.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
