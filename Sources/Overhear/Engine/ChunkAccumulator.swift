import Foundation

/// Re-slices a stream of arbitrary-length audio into fixed-size chunks.
///
/// The input device picks its own buffer size and it is rarely the 1280 samples
/// the wake word models were trained on, so buffers are accumulated here and
/// handed on only in whole chunks. Whatever is left over stays for the next
/// buffer: dropping the remainder would put a silent gap into the audio every
/// few frames, which reads to the detector as a word cut in half.
struct ChunkAccumulator {
    let chunkSize: Int
    private var pending: [Float] = []

    init(chunkSize: Int) {
        self.chunkSize = chunkSize
    }

    mutating func append<S: Sequence>(_ samples: S) -> [[Float]] where S.Element == Float {
        pending.append(contentsOf: samples)

        var chunks: [[Float]] = []
        var start = 0
        while pending.count - start >= chunkSize {
            chunks.append(Array(pending[start..<(start + chunkSize)]))
            start += chunkSize
        }
        if start > 0 {
            pending.removeFirst(start)
        }
        return chunks
    }

    mutating func reset() {
        pending.removeAll(keepingCapacity: true)
    }
}
