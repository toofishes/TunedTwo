# Architecture

## Target graph

```
TunedTwo (executable) ─┐
                       ├──► TunedTwoCore (library) ──► CNrsc5 (systemLibrary) ──► libnrsc5.dylib
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

## Sample I/Q file

`Vendor/nrsc5/support/sample.xz` is extracted by `scripts/prepare-sample.sh` into `Resources/sample.bin`. `build.sh` copies it into the app bundle so the app can play it without an RTL-SDR.

## Traffic / weather samples

`Resources/traffic_sample/` and `Resources/weather_sample/` are test/CLI data. The CLI takes a directory path and stitches traffic-map tiles; tests parse the sample config files. They are intentionally **not** bundled into the app.
