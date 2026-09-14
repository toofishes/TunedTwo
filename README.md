# TunedTwo

A native macOS HD Radio receiver built around the [`nrsc5`](https://github.com/theori-io/nrsc5) decoder.

The goal is a clean, SwiftUI-native app that feels at home on macOS — no Electron, no cross-platform UI toolkit. Audio is handled with `AVAudioEngine`, the GUI with SwiftUI + AppKit, and the decoder is the upstream `libnrsc5` dynamic library.

## Project status

Very early. The current focus is:

1. Solid build & run loop.
2. Audio playback from a sample I/Q file (no SDR required for development).
3. Frequency / subchannel input for live RTL-SDR reception.
4. Basic metadata display (station name, slogan, title/artist).

See [`TODO.md`](TODO.md) for the full roadmap and known loose ends.

## Requirements

- macOS 14.0+
- Xcode 16+ (or just the command-line tools plus `xcodegen`)
- Homebrew:
  - `cmake`, `libtool`, `pkg-config`
  - `fftw`, `librtlsdr`, `libusb` (runtime / link dependencies of `nrsc5`)
  - `xcodegen` (for regenerating the Xcode project)

`nrsc5` itself is vendored as a Git submodule under `Vendor/nrsc5` and is built locally by the project.

## Build

### Generate the Xcode project

```bash
xcodegen generate
```

### Build from the command line

```bash
xcodebuild -project TunedTwo.xcodeproj -scheme TunedTwo -configuration Debug build
```

### Run

```bash
open build/Debug/TunedTwo.app
```

Or run directly:

```bash
./build/Debug/TunedTwo.app/Contents/MacOS/TunedTwo
```

## Smoke test without an SDR

The project ships a build phase that extracts `Vendor/nrsc5/support/sample.xz` into the app bundle. Launch the app, enable **Use Sample File**, and press **Play**. You should hear KUT HD Radio audio and see station metadata.

## Project layout

- `Sources/TunedTwo/` – Swift source.
  - `Services/` – `TunerSession`, `AudioPlayer`, etc.
  - `Model/` – data models and observable app state.
  - `Views/` – SwiftUI views.
  - `Utilities/` – helpers (ring buffer, sample extraction, etc.)
- `Resources/` – Assets, Info.plist templates, sample files.
- `scripts/` – helper build/test scripts.
- `Vendor/nrsc5/` – Git submodule of the decoder.
- `Docs/` – architecture notes and references.

## License

TunedTwo itself will be MIT-licensed (or similar) once it stabilizes. `nrsc5` is GPL-3.0; linking against it means the distributed binary is also GPL-3.0.
