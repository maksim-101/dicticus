import XCTest
@testable import Dicticus

/// Regression net for D-01: a preview reads a copy of the capture buffer, and the final
/// decode at key release must still get every captured sample.
final class AudioSampleBufferSnapshotTests: XCTestCase {

    func testSnapshotTailIsNonDestructive() {
        let buffer = AudioSampleBuffer()
        buffer.append((1...10).map(Float.init))

        XCTAssertEqual(buffer.snapshotTail(maxSamples: 4), [7, 8, 9, 10])
        XCTAssertEqual(buffer.count, 10)
        XCTAssertEqual(buffer.drain(), (1...10).map(Float.init))
    }

    func testSnapshotTailLargerThanBufferReturnsEverything() {
        let buffer = AudioSampleBuffer()
        buffer.append((1...10).map(Float.init))

        XCTAssertEqual(buffer.snapshotTail(maxSamples: 100), (1...10).map(Float.init))
        XCTAssertEqual(buffer.count, 10)
    }

    func testSnapshotTailOfEmptyBufferIsEmpty() {
        let buffer = AudioSampleBuffer()
        XCTAssertEqual(buffer.snapshotTail(maxSamples: 5), [])
        XCTAssertEqual(buffer.count, 0)
    }

    func testConcurrentAppendKeepsEverySampleWhileSnapshotting() async {
        let buffer = AudioSampleBuffer()
        let chunks = 200
        let chunkSize = 480

        let writer = Task.detached {
            for chunk in 0..<chunks {
                let start = chunk * chunkSize
                buffer.append((start..<(start + chunkSize)).map(Float.init))
                if chunk % 20 == 0 { await Task.yield() }
            }
        }

        for _ in 0..<chunks {
            let snapshot = buffer.snapshotTail(maxSamples: 1000)
            // The writer appends consecutive values, so a consistent copy is consecutive.
            for pair in zip(snapshot, snapshot.dropFirst()) {
                XCTAssertEqual(pair.1, pair.0 + 1, "snapshot saw a torn or reordered append")
                if pair.1 != pair.0 + 1 { break }
            }
            await Task.yield()
        }
        await writer.value

        let all = buffer.drain()
        XCTAssertEqual(all.count, chunks * chunkSize)
        XCTAssertEqual(all, (0..<(chunks * chunkSize)).map(Float.init))
    }

    func testSnapshotFromIndexReturnsExactlyTheLaterSamplesAndTheEndIndex() {
        let buffer = AudioSampleBuffer()
        buffer.append((1...10).map(Float.init))

        let first = buffer.snapshot(from: 6)
        XCTAssertEqual(first.samples, [7, 8, 9, 10])
        XCTAssertEqual(first.end, 10)

        buffer.append([11, 12])
        let second = buffer.snapshot(from: first.end)
        XCTAssertEqual(second.samples, [11, 12])
        XCTAssertEqual(second.end, 12)
        XCTAssertEqual(buffer.count, 12, "snapshot(from:) drained the buffer")
    }

    func testSnapshotFromAtOrPastTheEndIsEmpty() {
        let buffer = AudioSampleBuffer()
        buffer.append((1...10).map(Float.init))

        XCTAssertEqual(buffer.snapshot(from: 10).samples, [])
        XCTAssertEqual(buffer.snapshot(from: 10).end, 10)
        XCTAssertEqual(buffer.snapshot(from: 99).samples, [])
        XCTAssertEqual(buffer.snapshot(from: 99).end, 10)
        XCTAssertEqual(AudioSampleBuffer().snapshot(from: 0).samples, [])
    }

    func testSnapshotFromZeroOrBelowReturnsEverything() {
        let buffer = AudioSampleBuffer()
        buffer.append((1...5).map(Float.init))

        XCTAssertEqual(buffer.snapshot(from: 0).samples, (1...5).map(Float.init))
        XCTAssertEqual(buffer.snapshot(from: -3).samples, (1...5).map(Float.init))
    }

    func testConcurrentAppendNeverTearsASnapshotFrom() async {
        let buffer = AudioSampleBuffer()
        let chunks = 200
        let chunkSize = 480

        let writer = Task.detached {
            for chunk in 0..<chunks {
                let start = chunk * chunkSize
                buffer.append((start..<(start + chunkSize)).map(Float.init))
                if chunk % 20 == 0 { await Task.yield() }
            }
        }

        var index = 0
        var collected: [Float] = []
        for _ in 0..<20_000 where collected.count < chunks * chunkSize {
            let part = buffer.snapshot(from: index)
            // Each read continues exactly where the previous one ended: end - count == index.
            XCTAssertEqual(part.end - part.samples.count, min(index, part.end))
            collected.append(contentsOf: part.samples)
            index = part.end
            await Task.yield()
        }
        await writer.value

        XCTAssertEqual(collected, (0..<(chunks * chunkSize)).map(Float.init))
    }
}
