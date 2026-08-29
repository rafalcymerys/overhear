import XCTest
@testable import Overhear

/// The detector's window is fixed at 1280 samples and a dropped or duplicated
/// sample shifts everything after it, so the re-slicing has to be exact.
final class ChunkAccumulatorTests: XCTestCase {
    func testEmitsNothingUntilAFullChunkIsAvailable() {
        var accumulator = ChunkAccumulator(chunkSize: 4)
        XCTAssertTrue(accumulator.append([1, 2, 3]).isEmpty)
        XCTAssertEqual(accumulator.append([4]), [[1, 2, 3, 4]])
    }

    func testSplitsALargeBufferIntoWholeChunks() {
        var accumulator = ChunkAccumulator(chunkSize: 2)
        XCTAssertEqual(accumulator.append([1, 2, 3, 4, 5]), [[1, 2], [3, 4]])
        XCTAssertEqual(accumulator.append([6]), [[5, 6]])
    }

    /// The property that matters: audio in equals audio out, in order, with
    /// nothing lost across buffer boundaries of awkward sizes.
    func testPreservesEverySampleInOrder() {
        var accumulator = ChunkAccumulator(chunkSize: 1280)
        let sizes = [1, 4096, 512, 7, 4096, 1279, 1281, 3000]
        let input = (0..<sizes.reduce(0, +)).map { Float($0) }

        var emitted: [Float] = []
        var offset = 0
        for size in sizes {
            let slice = Array(input[offset..<(offset + size)])
            offset += size
            for chunk in accumulator.append(slice) {
                XCTAssertEqual(chunk.count, 1280)
                emitted.append(contentsOf: chunk)
            }
        }

        XCTAssertEqual(emitted, Array(input.prefix(emitted.count)))
        XCTAssertLessThan(input.count - emitted.count, 1280, "at most a partial chunk should be held back")
    }

    func testResetDropsTheHeldRemainder() {
        var accumulator = ChunkAccumulator(chunkSize: 4)
        _ = accumulator.append([1, 2, 3])
        accumulator.reset()
        XCTAssertTrue(accumulator.append([4]).isEmpty)
        XCTAssertEqual(accumulator.append([5, 6, 7]), [[4, 5, 6, 7]])
    }
}
