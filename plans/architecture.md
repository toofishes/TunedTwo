# Architecture

## Target graph

```
TunedTwo (executable) ─┐
                       ├──► TunedTwoCore (library) ──► CNrsc5 (systemLibrary) ──► libnrsc5.a
TunedTwoCLI (executable) ┘                            ↑
                                                      │
                                               swift-collections

TunedTwoCLI also depends on:
  - swift-argument-parser
  - GRDB.swift

TunedTwoTests (testTarget) ──► TunedTwoCore
```

## State and concurrency

- `TunedTwoCore` is UI-independent. It owns the C decoder bridge (`Nrsc5Context`), audio playback (`AudioPlayer`), and the tuner session actor (`TunerSession`).
- `TunerSession` is an actor; all `libnrsc5` API calls happen on it. The C callback runs on the library's worker thread and only copies events into a `Sendable` value before yielding them into an `AsyncStream`.
- The SwiftUI app owns `TunerState` (an `@Observable` model) on `@MainActor` and passes events into it from the session.
- The CLI dispatches to the same core types without any UI.

## Threading & concurrency model

The app builds in Swift 6 strict concurrency with no `@unchecked Sendable`.

- **`TunerSession` is an actor.** All `libnrsc5` API calls (`open`, `start`, `stop`, `close`, `set_frequency`) are confined to it. The UI layer only reaches it through async calls, passing `Sendable` values (`TunerConfiguration` snapshots taken on the MainActor).
- **The nrsc5 C callback never touches Swift state directly.** The opaque pointer handed to `nrsc5_set_callback` is a plain `Nrsc5Context` bridge object. On the library's worker thread, the callback's only job is to copy the C event into a `Sendable` `TunerEvent` value (strings and PCM samples are copied while the C pointers are valid) and yield it into an `AsyncStream`.
- **A single long-lived consumer task** drains that stream into the session actor. It holds the session weakly, so releasing the session does not keep it alive.
- **Teardown is RAII.** `Nrsc5Context.close()` unregisters the callback, joins the worker thread, and closes the C session; the context's own `deinit` finishes the event stream, which ends the consumer task. Even a running session that is dropped without `stop()` cannot leak the worker thread or the device.
- **`AudioPlayer` is an actor** that owns `AVAudioEngine` + `AVAudioPlayerNode`. Decoded PCM flows worker thread → stream → session actor → audio actor → system audio graph; nothing audio-related runs on the main thread.
- **UI state is `@MainActor`.** `TunerState` conforms to `TunerEventSink`; the session calls it only via `await` (and holds it weakly), so the compiler guarantees the nrsc5 callback can never mutate UI-owned state directly.

## Data flow

```
libnrsc5 worker thread
        │
        ▼
Nrsc5Context.eventHandler   (copies C pointers while valid)
        │
        ▼
AsyncStream<TunerEvent>
        │
        ▼
TunerSession consumer task  (actor-isolated)
        │
        ▼
MainActor TunerState / CLI sink
```

## Program/subchannel selection

`libnrsc5` decodes all HD Radio programs simultaneously. `TunerSession` stores a `currentProgram` inside the actor and filters `NRSC5_EVENT_AUDIO` and `NRSC5_EVENT_ID3` events by `event.program`. Switching programs calls `AudioPlayer.flush()` (stop + play on the player node, keeping the engine running) so the old program doesn't bleed through.

## Audio format

- Decoder output: interleaved 16-bit signed PCM, 44.1 kHz, stereo.
- `AudioPlayer` converts the samples to float and schedules buffers on an `AVAudioPlayerNode` connected to `AVAudioEngine.mainMixerNode`.

## Sample I/Q file

`Vendor/nrsc5/support/sample.xz` is extracted by the Makefile into `Resources/sample.bin` for tests and the smoke-test script. The app no longer bundles the sample. To play from a file, launch the app with `TUNEDTWO_SAMPLE_FILE=/path/to/sample.bin`; the UI replaces the frequency field with the sample file name while it is playing.

## Traffic / weather samples

`Resources/ttm_traffic/` and `Resources/ttm_weather/` (TTM) and `Resources/here_traffic/` and `Resources/here_weather/` (HERE) are test/CLI data. The CLI takes a directory path and stitches traffic-map tiles; tests parse the sample config files. They are intentionally **not** bundled into the app.

## Known limitations / next steps

- RTL-SDR support is present but untested (needs a physical device).
- No window-state persistence yet.
- The `libnrsc5` build still uses CMake via `scripts/build-nrsc5.sh`; making it native to SwiftPM is tracked in [`plans/nrsc5-native-build.md`](plans/nrsc5-native-build.md).
