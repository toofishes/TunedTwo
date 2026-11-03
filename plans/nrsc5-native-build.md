# Native C-library build (follow-on plan)

**Status:** not started. This file is a placeholder to capture the goal and candidate approaches.

## Goal

Make `libnrsc5` buildable by SwiftPM itself, removing the build-time dependency on Homebrew tools (`cmake`, `libtool`, `pkg-config`) and making `swift build` fully self-contained.

## Current state

- `Vendor/nrsc5` is a Git submodule.
- `scripts/build-nrsc5.sh` invokes CMake and builds `libnrsc5.dylib`.
- The Makefile builds `libnrsc5.dylib` as a pre-step before any Swift compilation.
- Runtime linking is already Homebrew-free: the dylib depends only on system frameworks.

So the follow-on is about **build-time** self-containment, not runtime linking.

## Candidate approaches

1. **SwiftPM build-tool plugin**
   - Keep the CMake build, but invoke `scripts/build-nrsc5.sh` automatically during `swift build`.
   - Does not eliminate the Homebrew tool dependency, but removes the separate Makefile step.

2. **XCFramework binary target**
   - Build `libnrsc5.dylib` + header into an XCFramework (e.g. in CI) and consume it via `.binaryTarget`.
   - Clean for SwiftPM, but still needs a build environment somewhere to produce the XCFramework.

3. **SwiftPM C target from submodule sources**
   - Add a `.target` that compiles the `nrsc5` C sources directly.
   - The hard part is its dependencies (`faad2`, `fftw`, `libusb`, `rtlsdr`), which today are built by CMake `ExternalProject`.
   - Options:
     - Vendor/break out each dependency as its own SwiftPM C target.
     - Prebuild a static `libnrsc5.a` that statically links all deps and consume that as a binary target.

## Decision record

*To be filled in when work starts.*
