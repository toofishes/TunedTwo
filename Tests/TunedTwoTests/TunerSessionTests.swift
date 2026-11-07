//
//  TunerSessionTests.swift
//  TunedTwoTests
//
//  Smoke tests for the tuner session lifecycle.
//

import Foundation
import Testing

@testable import TunedTwoCore

private final class MockTunerEventSink: TunerEventSink, Sendable {
    func tunerSessionDidEmit(_ event: TunerEvent) async {}
}

@Suite("Sample file streaming")
struct SampleFileStreamTests {
    private func withTemporaryFile<T>(_ bytes: Data, _ body: (URL) async throws -> T) async throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tunedtwo-sample-\(UUID().uuidString).bin")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try await body(url)
    }

    @Test("streams a file in bounded chunks without loading it whole")
    func streamsBoundedChunks() async throws {
        let chunkSize = 64 * 1024
        let data = Data((0..<(chunkSize * 2 + 17)).map { UInt8(truncatingIfNeeded: $0) })

        try await withTemporaryFile(data) { url in
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            var assembled = Data()
            var chunkCount = 0
            for try await chunk in handle.dataChunks(ofSize: chunkSize) {
                #expect(chunk.count > 0 && chunk.count <= chunkSize)
                assembled.append(contentsOf: chunk)
                chunkCount += 1
            }

            #expect(chunkCount == 3)
            #expect(assembled == data)
        }
    }

    @Test("finishes immediately for an empty file")
    func emptyFile() async throws {
        try await withTemporaryFile(Data()) { url in
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            for try await _ in handle.dataChunks(ofSize: 64 * 1024) {
                Issue.record("Expected no chunks from an empty file")
            }
        }
    }

    /// Also proves the sequence is pull-based: no read happens until iteration,
    /// so a handle closed beforehand surfaces its error on the first `next()`.
    @Test("propagates read errors instead of failing through errno")
    func readErrorsAreThrown() async throws {
        try await withTemporaryFile(Data([1, 2, 3])) { url in
            let handle = try FileHandle(forReadingFrom: url)
            let chunks = handle.dataChunks(ofSize: 64 * 1024)
            try handle.close()

            do {
                for try await _ in chunks {}
                Issue.record("Expected reading a closed handle to throw")
            } catch {
                #expect(!error.localizedDescription.isEmpty)
            }
        }
    }
}

@Suite("TunerSession lifecycle")
struct TunerSessionTests {
    /// Initializing and releasing a `TunerSession` exercises the wiring
    /// between the actor, the `AudioPlayer`, the `Nrsc5Context`, and the
    /// background event consumers. It does not require an RTL-SDR or an
    /// audio output device because playback is never started; the
    /// `AudioPlayer` is only constructed (not started), and the
    /// `Nrsc5Context` only creates its event stream.
    @Test("initializes and tears down without hardware")
    func initializesAndTearsDown() async {
        let sink = MockTunerEventSink()
        let session = TunerSession(sink: sink)
        await session.setProgram(1)
        await session.stop()
    }
}
