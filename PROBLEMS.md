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

Every target that ultimately links `libnrsc5` needs its own `-L` search path and rpath flags, even if it depends on `TunedTwoCore` which already specifies them. The current `Package.swift` defines a shared `nrsc5LinkerSettings` array and applies it to `TunedTwoCore`, `TunedTwo`, `TunedTwoCLI`, and `TunedTwoTests`.

## `swift build` does not build every executable product by default

`swift build -c debug` produced `TunedTwo` but not `tunedtwo-cli` until we passed `--product TunedTwo --product tunedtwo-cli`. `build.sh` now does this explicitly so both binaries are available for bundling.

## The copied CLI binary name follows the product name, not the target name

The SwiftPM target is `TunedTwoCLI`, but the produced executable is `tunedtwo-cli` (matching the product name). `build.sh` and the `Makefile` look for `tunedtwo-cli` in the build products directory, not `TunedTwoCLI`.

## Hardened runtime needs library-validation exception for ad-hoc-signed dylibs

`TunedTwo/TunedTwo.entitlements` includes `com.apple.security.cs.disable-library-validation` so the locally-built, ad-hoc-signed `libnrsc5.dylib` can be loaded. For a real Developer ID signed release, sign the dylib with the same identity and re-evaluate whether this exception is still required.

## Resources live at the repo root, not in a SwiftPM target bundle

`traffic_sample/` and `weather_sample/` remain at `Resources/` because the CLI takes filesystem paths and tests locate them relative to `#filePath`. The sample directories are test/CLI data, not runtime app resources; the app only plays a sample file when launched with `TUNEDTWO_SAMPLE_FILE`.
