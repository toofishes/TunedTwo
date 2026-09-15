# TunedTwo Architecture Notes

## Overview

TunedTwo is a native macOS app built with SwiftUI and AppKit, wrapping the `libnrsc5` HD Radio decoder. Audio output uses `AVAudioEngine` / `AVAudioPlayerNode` so everything is macOS-native.

## Project layout

- `Sources/TunedTwo/`
  - `TunedTwoApp.swift` – App entry point, `@main`, `AppDelegate`.
  - `Views/ContentView.swift` – SwiftUI main window.
  - `Model/TunerState.swift` – `@MainActor` observable app state (frequency, program, metadata, signal stats). Receives tuner events via `TunerEventSink`.
  - `Services/TunerEvent.swift` – `Sendable` event vocabulary + `TunerEventSink` protocol (the tuner → UI contract).
  - `Services/TunerSession.swift` – `actor` wrapping `libnrsc5` lifecycle and C callback handling.
  - `Services/AudioPlayer.swift` – `actor` owning the `AVAudioEngine` PCM playback graph.
  - `Utilities/SampleFileProvider.swift` – Locates the bundled sample I/Q file.
- `TunedTwo-Bridging-Header.h` – exposes `nrsc5.h` to Swift.
- `project.yml` – XcodeGen spec for the native `.xcodeproj`.
- `scripts/` – build nrsc5, prepare sample, run smoke test.
- `Vendor/nrsc5` – Git submodule of the decoder (pinned to v3.2.0).

## Build flow

1. `xcodegen generate` creates `TunedTwo.xcodeproj` from `project.yml`.
2. Xcode prebuild scripts run:
   - `scripts/prepare-sample.sh` extracts `Vendor/nrsc5/support/sample.xz` → `Resources/sample.bin`.
   - `scripts/build-nrsc5.sh` builds `libnrsc5.dylib` from the submodule.
3. The app target links `-lnrsc5` and copies the dylib into `Contents/Frameworks` at build time.

## Threading & concurrency model (Swift 6, strict concurrency)

The app builds in the Swift 6 language mode with no `@unchecked Sendable`.

- **`TunerSession` is an actor.** All `libnrsc5` API calls (`open`, `start`,
  `stop`, `close`, `set_frequency`) are confined to it. The UI layer only
  reaches it through async calls, passing `Sendable` values
  (`TunerConfiguration` snapshots taken on the MainActor). UI actions do
  not need to be synchronous: play/stop, program switches, and debounced
  live retunes are fire-and-forget commands, and failures flow back up as
  `.failed` events.
- **The nrsc5 C callback never touches Swift state directly.** The opaque
  pointer handed to `nrsc5_set_callback` is a plain `Nrsc5Context` bridge
  object. On the library's worker thread, the callback's only job is to copy
  the C event into a `Sendable` `TunerEvent` value (strings and PCM samples
  are copied while the C pointers are valid) and yield it into an
  `AsyncStream`.
- **A single long-lived consumer task** drains that stream into the session
  actor (`for await … { await self?.handle(…) }`). It holds the session
  weakly, so releasing the session does not keep it alive.
- **Teardown is RAII.** `Nrsc5Context.close()` unregisters the callback, joins
  the worker thread, and closes the C session; the context's own `deinit`
  additionally finishes the event stream, which ends the consumer task. So
  even a running session that is dropped without `stop()` cannot leak the
  worker thread or the device. The mutable C state is only ever touched from
  the session actor's methods and the context's `deinit` — these can never
  overlap (an in-flight actor method keeps the session, and therefore the
  context, alive) — which is why no locks are needed anywhere.
- **Audio is background-only.** `AudioPlayer` is an actor that owns
  `AVAudioEngine` + `AVAudioPlayerNode`. Decoded PCM flows worker thread →
  stream → session actor → audio actor → system audio graph; nothing audio
  related runs on the main thread.
- **UI state is `@MainActor`.** `TunerState` conforms to `TunerEventSink`;
  the session calls it only via `await` (and holds it weakly), so the
  compiler guarantees the nrsc5 callback can never mutate UI-owned state
  directly.

## Program/subchannel selection

`libnrsc5` decodes all HD Radio programs simultaneously. `TunerSession` stores a `currentProgram` inside the actor and filters `NRSC5_EVENT_AUDIO` and `NRSC5_EVENT_ID3` events by `event.program`. Switching programs calls `AudioPlayer.flush()` (stop + play on the player node, keeping the engine running) so the old program doesn't bleed through.

## Audio format

- Decoder output: interleaved 16-bit signed PCM, 44.1 kHz, stereo.
- `AudioPlayer` (an actor) converts the samples to float and schedules buffers on an `AVAudioPlayerNode` connected to `AVAudioEngine.mainMixerNode`.

## Smoke test

Setting `TUNEDTWO_SMOKE_TEST=1` makes the app auto-play the bundled sample file and self-terminate after ~8 seconds, printing `SMOKE_OK` if metadata was received. `scripts/smoke-test.sh` automates this.

## Known limitations / next steps

- RTL-SDR support is present but untested (needs a physical device).
- No app icon, asset catalog, or window-state persistence yet.
- The sample-file input decodes as fast as the CPU allows (libnrsc5 does not
  throttle file playback), so the whole file is decoded and queued quickly;
  real-time pacing for file input is TBD.
- No spectrum / weather / traffic / album-art yet.
- Runtime dependencies (`libfftw3f`, `librtlsdr`) are currently expected via Homebrew absolute paths; distribution bundling is TBD.
