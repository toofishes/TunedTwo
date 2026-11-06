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

### 2026-11-05 — Baby step: clean up the SwiftPM / C-library boundary

Before trying to make `libnrsc5` build natively inside SwiftPM, we simplified the existing wrapper so the boundary is easier to reason about:

- Kept `CNrsc5` as a separate `systemLibrary` target. A Swift target cannot directly expose a C header/module, so a dedicated Clang/systemLibrary target is still required. It also isolates the C API cleanly.
- Removed the `Sources/CNrsc5/shim.h` indirection and pointed `module.modulemap` directly at `Vendor/nrsc5/include/nrsc5.h`. For a single upstream header the shim added no value.
- Removed the redundant `.linkedLibrary("nrsc5")` from `Package.swift`; the module map's `link "nrsc5"` directive already tells the linker to link `-lnrsc5`.
- Kept the explicit `-L` and rpath `unsafeFlags` on every target that links `libnrsc5.dylib`, because SwiftPM does not propagate `unsafeFlags` across target boundaries.

### Why not a build-tool plugin as the first step

A SwiftPM build-tool plugin is not a natural fit for building a prebuilt `.dylib`:

- Build plugins are oriented around generating source files that feed into a target's compile, not producing a sidecar dynamic library.
- They run sandboxed and write outputs to a plugin-specific derived directory, while our manifest needs a static library search path (`Vendor/nrsc5/build/src`).
- Moving CMake invocation out of the Makefile would not eliminate the Homebrew tool dependency (`cmake`, `libtool`, etc.); it would only relocate it.

Therefore the first integration step is cleanup, not a plugin.

### Future options (unchanged)

1. **XCFramework / prebuilt binary target** — build a static `libnrsc5.a` that statically links `faad2`, `fftw`, `libusb`, and `rtlsdr`, then consume it via `.binaryTarget` or a system-library wrapper. This is the most likely next baby step.
2. **SwiftPM C targets from submodule sources** — vendor each CMake dependency as its own SwiftPM C target. This is the most "native" approach but is a large project because of `faad2`, `fftw`, `libusb`, and `rtlsdr`.
3. **Keep CMake** — leave `scripts/build-nrsc5.sh` as the source-of-truth C build and accept the Makefile pre-step. This remains viable if the other options prove too costly.
