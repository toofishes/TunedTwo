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

- macOS 26.0+
- Xcode 27+ or the Swift 6.4+ toolchain
- Homebrew:
  - `cmake`, `libtool`, `pkg-config`
  - `swift-format` (optional, for `make format`)

`nrsc5` itself is vendored as a Git submodule under `Vendor/nrsc5` and is built locally by the project.

## Build

This repo uses **Swift Package Manager** as the source of truth. There is no checked-in `.xcodeproj`; open the repo in Xcode with **File → Open Package** if you want to use the IDE.

```sh
make check   # fast compile-only gate
make test    # headless tests
make build   # build/TunedTwo.app + build/tunedtwo-cli
make run     # build and launch the app
make cli     # build the command-line tool
```

See `make help` for everything else, including the release pipeline.

### First-time setup

```sh
git submodule update --init --recursive
scripts/build-nrsc5.sh   # or let 'make' run it automatically
```

## Smoke test without an SDR

The project ships a sample I/Q file extracted from `Vendor/nrsc5/support/sample.xz`. Launch the app, enable **Use Sample File**, and press **Play**. You should hear KUT HD Radio audio and see station metadata.

There is also a scripted smoke test:

```sh
./scripts/smoke-test.sh
```

## Tests

Unit tests live in `Tests/TunedTwoTests` and run **headless** — the test bundle links only against `TunedTwoCore`, so running tests never launches the app:

```sh
make test
```

## CLI (`tunedtwo-cli`)

The `tunedtwo-cli` command-line tool exercises the same `TunedTwoCore` code paths without any UI. Build it with:

```sh
make cli
```

Examples:

```sh
# Extract the bundled sample and listen to it (HD1 by default):
make Resources/sample.bin
build/tunedtwo-cli listen-file Resources/sample.bin

# Or select another zero-indexed subprogram:
build/tunedtwo-cli listen-file /path/to/capture.cu8 --subprogram 1

# For a live RTL-SDR station (HD1 by default; --subprogram is optional):
build/tunedtwo-cli listen 93.1 --subprogram 1

# Stitch the sample TTM traffic tiles to stdout (pipe it somewhere):
build/tunedtwo-cli traffic-map Resources/ttm_traffic | open -f -a Preview

# Or write a file, with per-tile reporting:
build/tunedtwo-cli traffic-map Resources/ttm_traffic -o out.png -v
```

Run `build/tunedtwo-cli --help` or `build/tunedtwo-cli traffic-map --help` for details.

## Project layout

- `Package.swift` — SwiftPM manifest; source of truth for targets, dependencies, and linker settings.
- `Sources/TunedTwoCore/` — UI-independent core: links `libnrsc5` and builds as a library.
  - `Services/` — `TunerSession`, `AudioPlayer`, etc.
  - `Model/` — data models and observable app state.
  - `Utilities/` — helpers (bundled sample file lookup, etc.)
- `Sources/TunedTwo/` — the SwiftUI app.
- `Sources/TunedTwoCLI/` — `tunedtwo-cli` command-line tool.
- `Sources/CNrsc5/` — SwiftPM system-library wrapper bridging the vendored C API.
- `Tests/TunedTwoTests/` — headless unit tests.
- `Resources/` — `Info.plist`, bundled sample I/Q file, and sample traffic/weather data (`ttm_traffic/`, `ttm_weather/`, `here_traffic/`, `here_weather/`).
- `scripts/` — helper build/test scripts.
- `Vendor/nrsc5/` — Git submodule of the decoder.
- `plans/` — architecture, build-system, and migration notes.

## License

TunedTwo itself will be MIT-licensed (or similar) once it stabilizes. `nrsc5` is GPL-3.0; linking against it means the distributed binary is also GPL-3.0.
