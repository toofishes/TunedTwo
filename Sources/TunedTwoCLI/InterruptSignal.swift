//
//  InterruptSignal.swift
//  TunedTwo
//
//  Single SIGINT handler for the CLI listen commands.
//

import Dispatch
import Foundation

/// Returns an async stream that yields once when the process receives `SIGINT`.
///
/// The returned stream disables the default signal handling so that callers can
/// await the interrupt instead of being terminated. Cancelling iteration (or
/// otherwise terminating the stream) tears down the underlying dispatch source.
func interruptSignalStream(_ signum: Int32 = SIGINT) -> AsyncStream<Void> {
    signal(signum, SIG_IGN)
    return AsyncStream { continuation in
        let source = DispatchSource.makeSignalSource(signal: signum, queue: .main)
        source.setEventHandler {
            continuation.yield(())
            continuation.finish()
        }
        continuation.onTermination = { _ in
            source.cancel()
        }
        source.resume()
    }
}
