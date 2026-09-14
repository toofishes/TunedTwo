# TunedTwo Architecture Notes

## Overview

TunedTwo is a native macOS app built with SwiftUI and AppKit, wrapping the `libnrsc5` HD Radio decoder. Audio output uses `AVAudioEngine` / `AVAudioPlayerNode` so everything is macOS-native.

## Project layout

- `Sources/TunedTwo/`
  - `TunedTwoApp.swift` – App entry point, `@main`, `AppDelegate`.
  - `Views/ContentView.swift` – SwiftUI main window.
  - `Model/TunerState.swift` – Observable app state (frequency, program, metadata, signal stats).
  - `Services/TunerSession.swift` – `libnrsc5` lifecycle and C callback handling.
  - `Services/AudioPlayer.swift` – `AVAudioEngine` PCM playback.
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

## Threading model

- `TunerSession` owns a serial `DispatchQueue` for all `libnrsc5` API calls (`open`, `start`, `stop`, `close`).
- `libnrsc5` invokes the C callback from its internal worker thread.
- The callback copies any C strings immediately (they are only valid for the duration of the callback) and then dispatches UI updates to the main queue.
- Audio PCM is fed to `AudioPlayer` from the callback thread; `AudioPlayer` schedules buffers on its own serial queue.

## Program/subchannel selection

`libnrsc5` decodes all HD Radio programs simultaneously. The app stores a `currentProgram` and filters `NRSC5_EVENT_AUDIO` / `NRSC5_EVENT_ID3` by `event.audio.program`. Switching programs flushes queued audio so the old program doesn't bleed through.

## Audio format

- Decoder output: interleaved 16-bit signed PCM, 44.1 kHz, stereo.
- `AudioPlayer` converts to float and schedules buffers on an `AVAudioPlayerNode` connected to `AVAudioEngine.mainMixerNode`.

## Smoke test

Setting `TUNEDTWO_SMOKE_TEST=1` makes the app auto-play the bundled sample file and self-terminate after ~8 seconds, printing `SMOKE_OK` if metadata was received. `scripts/smoke-test.sh` automates this.

## Known limitations / next steps

- RTL-SDR support is present but untested (needs a physical device).
- No app icon, asset catalog, or window-state persistence yet.
- No spectrum / weather / traffic / album-art yet.
- Runtime dependencies (`libfftw3f`, `librtlsdr`) are currently expected via Homebrew absolute paths; distribution bundling is TBD.
