# Problems — things that bit us

Project-specific hard-won lessons. Generic SwiftUI rules live elsewhere if they accumulate; this file is for issues specific to TunedTwo.

---

## SwiftPM linker flags must use `-Xlinker`, not `-Wl,`

`swiftc` does not accept `-Wl,-rpath,…` directly. In `Package.swift` `linkerSettings`, pass rpaths as:

```swift
.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
```

Using `-Wl,…` produces `error: unknown argument` from the Swift compiler.

## `unsafeFlags` are not propagated across SwiftPM target boundaries

Every target that ultimately links `libnrsc5` needs its own `-L` search path, even if it depends on `TunedTwoCore` which already specifies it. The current `Package.swift` defines a shared `nrsc5LibrarySearchPath` array and applies it to `TunedTwoCore`, `TunedTwo`, `TunedTwoCLI`, and `TunedTwoTests`. (The old dylib-based build also needed per-target rpath flags; those are gone now that the library is statically linked.)

## Multiple `--product` flags are not additive

`swift build --product TunedTwo --product tunedtwo-cli` only builds the last product (`tunedtwo-cli`); SwiftPM ignores all but the final `--product` value. `build.sh` therefore runs a separate `swift build --product …` invocation for each executable product instead of passing both flags at once.

## The copied CLI binary name follows the product name, not the target name

The SwiftPM target is `TunedTwoCLI`, but the produced executable is `tunedtwo-cli` (matching the product name). `build.sh` and the `Makefile` look for `tunedtwo-cli` in the build products directory, not `TunedTwoCLI`.

## Hardened runtime and locally-built libraries

`libnrsc5` is now statically linked, so there is no locally-built `libnrsc5.dylib` to load at runtime and no `com.apple.security.cs.disable-library-validation` exception is required for it. The remaining hardened-runtime entitlements in `TunedTwo/TunedTwo.entitlements` are for app sandboxing and USB device access.

## Resources live at the repo root, not in a SwiftPM target bundle

`traffic_sample/` and `weather_sample/` remain at `Resources/` because the CLI takes filesystem paths and tests locate them relative to `#filePath`. The sample directories are test/CLI data, not runtime app resources; the app only plays a sample file when launched with `TUNEDTWO_SAMPLE_FILE`.

## `make run` can launch a stale Xcode/DerivedData build

Xcode and the Makefile both produce a `TunedTwo.app` with bundle ID `io.tunedtwo.TunedTwo`. Xcode registers its `DerivedData` copy with LaunchServices, so `open build/TunedTwo.app` may resolve to a stale or non-existent Xcode build instead of the freshly-built Makefile app.

Quick fix:

```bash
lsregister -u /Users/dmcgee/projects/tunedtwo/DerivedData/Build/Products/Debug/TunedTwo.app
make register
```

Longer-term options:
- Launch the executable directly in `make run` (`"$(APP)/Contents/MacOS/$(APP_NAME)" &`) to bypass LaunchServices entirely.
- Use a distinct bundle ID (e.g. `io.tunedtwo.TunedTwo.dev`) for Makefile dev builds.
