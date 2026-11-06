# Native C-library build (follow-on plan)

**Status:** in progress. The SwiftPM/C boundary has been cleaned up and the build now links a self-contained static `libnrsc5.a` instead of a dylib.

## Goal

Make `libnrsc5` buildable by SwiftPM itself, removing the build-time dependency on Homebrew tools (`cmake`, `libtool`, `pkg-config`) and making `swift build` fully self-contained.

## Current state

- `Vendor/nrsc5` is a Git submodule.
- `scripts/build-nrsc5.sh` invokes CMake and produces `Vendor/nrsc5/build/static/libnrsc5.a`, a single self-contained static archive that includes nrsc5 plus its built-in dependencies (`faad2`, `fftw`, `rtlsdr`, `libusb`).
- The Makefile builds `libnrsc5.a` as a pre-step before any Swift compilation.
- `Package.swift` links the static archive with `-L Vendor/nrsc5/build/static`.
- Runtime linking is already Homebrew-free; the final executable depends only on system frameworks it already links transitively.

So the follow-on is about **build-time** self-containment, not runtime linking.

## Candidate approaches

1. **SwiftPM build-tool plugin**
   - Keep the CMake build, but invoke `scripts/build-nrsc5.sh` automatically during `swift build`.
   - Does not eliminate the Homebrew tool dependency, but removes the separate Makefile step.
   - Not a natural fit: build plugins are designed to generate source files, not to produce a sidecar static library with a fixed path that the manifest already references.

2. **Prebuilt binary target**
   - Build the static `libnrsc5.a` (e.g. in CI) and ship it as a local `.binaryTarget` or remote artifact.
   - Clean for SwiftPM and makes `swift build` fully self-contained, but still needs a build environment somewhere to produce the archive.
   - Could be checked into the repo, but that adds ~3.4 MB of binary data to git history and requires refreshing when the `Vendor/nrsc5` submodule or supported architectures change.

3. **SwiftPM C target from submodule sources**
   - Add a `.target` that compiles the `nrsc5` C sources directly.
   - The hard part is its dependencies (`faad2`, `fftw`, `libusb`, `rtlsdr`), which today are built by CMake `ExternalProject`.
   - Options:
     - Vendor/break out each dependency as its own SwiftPM C target.
     - Prebuild a static `libnrsc5.a` that statically links all deps and consume it via a system-library wrapper or binary target.

## Decision record

### 2026-11-05 — Baby step: clean up the SwiftPM / C-library boundary

Before trying to make `libnrsc5` build natively inside SwiftPM, we simplified the existing wrapper so the boundary is easier to reason about:

- Kept `CNrsc5` as a separate `systemLibrary` target. A Swift target cannot directly expose a C header/module, so a dedicated Clang/systemLibrary target is still required. It also isolates the C API cleanly.
- Removed the `Sources/CNrsc5/shim.h` indirection and pointed `module.modulemap` directly at `Vendor/nrsc5/include/nrsc5.h`. For a single upstream header the shim added no value.
- Removed the redundant `.linkedLibrary("nrsc5")` from `Package.swift`; the module map's `link "nrsc5"` directive already tells the linker to link `-lnrsc5`.
- Kept the explicit `-L` `unsafeFlags` on every target that links `libnrsc5.a`, because SwiftPM does not propagate `unsafeFlags` across target boundaries.

### Why not a build-tool plugin as the first step

A SwiftPM build-tool plugin is not a natural fit for building a prebuilt `.a`:

- Build plugins are oriented around generating source files that feed into a target's compile, not producing a sidecar static library.
- They run sandboxed and write outputs to a plugin-specific derived directory, while our manifest needs a static library search path (`Vendor/nrsc5/build/static`).
- Moving CMake invocation out of the Makefile would not eliminate the Homebrew tool dependency (`cmake`, `libtool`, etc.); it would only relocate it.

Therefore the first integration step is cleanup, not a plugin.

### 2026-11-05 — Switched from dylib to static `libnrsc5.a`

After prototyping, we moved the build from a dynamic `libnrsc5.dylib` to a merged static `libnrsc5.a`:

- `scripts/build-nrsc5.sh` now runs `libtool -static` to merge `libnrsc5_static.a` with the static archives for `faad2`, `fftw`, `rtlsdr`, and `libusb` into `Vendor/nrsc5/build/static/libnrsc5.a`.
- `Package.swift` now links `-L Vendor/nrsc5/build/static`; the build-tree rpath was removed because the static archive is resolved at link time. The system frameworks that `libusb` uses (`CoreFoundation`, `IOKit`, `Security`) are already linked transitively by the Swift runtime and app frameworks, so no explicit framework links are required.
- `build.sh` and the `Makefile` no longer copy `libnrsc5.dylib` into the app bundle or CLI output directory.
- `TunedTwo.entitlements` no longer needs library-validation exceptions for nrsc5 (the pending entitlement change in the working tree reflects this).

This does not yet make `swift build` self-contained — CMake and the Homebrew tools are still required — but it removes the dylib/rpath complexity and creates a single artifact that is much easier to check in or ship as a binary target later.

### 2026-11-05 — Fixed runtime crash by pinning the C-library deployment target and disabling `pipe2`

After switching to the static archive, `tunedtwo-cli listen` and the GUI "Play" button crashed with `EXC_BAD_ACCESS` at address `0x0` inside `libusb_init_context` → `usbi_io_init` → `usbi_create_event`. The backtrace showed a NULL function pointer call.

Root cause: libusb's `configure` detected `pipe2` as available because the macOS 27 SDK declares it in `<unistd.h>`, but on macOS 26 (our deployment target) `pipe2` is only a weak stub that resolves to `NULL` at runtime. When statically linked, the stub is called directly and segfaults. With the dynamic library, the same weak stub would also be `NULL`, but in practice the previous dylib build either used a different SDK/deployment target or the failure mode was masked.

Fix in `scripts/build-nrsc5.sh`:

- Export `MACOSX_DEPLOYMENT_TARGET=26.0` so the C libraries target the same OS version as the Swift package.
- Export `ac_cv_func_pipe2=no` so libusb's `configure` does not detect the weak `pipe2` stub and falls back to `pipe()` + `fcntl(FD_CLOEXEC)`.

### Future options

1. **Prebuilt binary target** — build `libnrsc5.a` in CI (or manually), check it into the repo or host it, and consume it via `.binaryTarget` or the existing `CNrsc5` wrapper. This is the most likely next step if we want `swift build` to work without CMake.
2. **SwiftPM C targets from submodule sources** — vendor each CMake dependency as its own SwiftPM C target. This is the most "native" approach but is a large project because of `faad2`, `fftw`, `libusb`, and `rtlsdr`.
3. **Keep CMake / on-demand static build** — leave `scripts/build-nrsc5.sh` as the source-of-truth C build and accept the Makefile pre-step. This is the current state and remains viable if the other options prove too costly.
