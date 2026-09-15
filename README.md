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

The Xcode project is generated from [`project.yml`](project.yml) using [XcodeGen](https://github.com/yonaskolb/XcodeGen). **`project.yml` is the source of truth** for deployment target, build settings, script phases, search paths, etc. — the checked-in `.xcodeproj` is a generated artifact.

Regenerate whenever you change `project.yml`:

```bash
scripts/prepare-sample.sh
xcodegen generate
```

Notable settings:

- `ENABLE_USER_SCRIPT_SANDBOXING: NO` — required so script phases can find `/opt/homebrew/bin` (cmake, etc.)
- `export PATH="$PATH:/opt/homebrew/bin"` — prepended in the build-nrsc5 script phase
- Script `.sh` sources listed as `inputFiles` (dependency tracking)

After running `xcodegen generate`, diff the result (`git diff TunedTwo.xcodeproj/`) and verify these settings are preserved before committing.

### Build from the command line

```bash
xcodebuild -project TunedTwo.xcodeproj -scheme TunedTwo -configuration Debug -derivedDataPath DerivedData build
```

### Run

```bash
open DerivedData/Build/Products/Debug/TunedTwo.app
```

Or run directly:

```bash
./DerivedData/Build/Products/Debug/TunedTwo.app/Contents/MacOS/TunedTwo
```

## Smoke test without an SDR

The project ships a build phase that extracts `Vendor/nrsc5/support/sample.xz` into the app bundle. Launch the app, enable **Use Sample File**, and press **Play**. You should hear KUT HD Radio audio and see station metadata.

## Project layout

- `Sources/TunedTwo/` – Swift source.
  - `Services/` – `TunerSession`, `AudioPlayer`, etc.
  - `Model/` – data models and observable app state.
  - `Views/` – SwiftUI views.
  - `Utilities/` – helpers (bundled sample file lookup, etc.)
- `Resources/` – bundled sample I/Q file.
- `scripts/` – helper build/test scripts.
- `Vendor/nrsc5/` – Git submodule of the decoder.
- `Docs/` – architecture notes and references.

## License

TunedTwo itself will be MIT-licensed (or similar) once it stabilizes. `nrsc5` is GPL-3.0; linking against it means the distributed binary is also GPL-3.0.
