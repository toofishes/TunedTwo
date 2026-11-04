# Progress

Running log of meaningful changes. Newest first.

---

## 2026-11-04 — Added tuner coverage tests

Added headless smoke tests for `nameForDSDMIMEType`, `TunerSession`
initialization/teardown, and `Nrsc5Context` decoding the bundled
`sample.bin` with a stubbed audio sink. Fixed `SampleFileProvider`'s
dev fallback so SwiftPM tests can locate `Resources/sample.bin`.

## 2026-11-04 — Raised minimum target to macOS 26

Bumped the deployment target and toolchain floor to match the host SDK and modern control behaviors.

## 2026-11-03 — Migrated to SwiftPM-first build

Replaced the XcodeGen-generated `.xcodeproj` with a root-level `Package.swift` and a `Makefile`/`build.sh` workflow modeled on [tqbf/swiftui-app](https://github.com/tqbf/swiftui-app).

The `libnrsc5` CMake build remains a Makefile pre-step. Making it native to SwiftPM is the next major follow-on.
