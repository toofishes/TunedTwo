# Progress

Running log of meaningful changes. Newest first.

---

## 2026-11-05 — Fixed `make release` for SwiftPM 6.4

`build.sh` no longer passes multiple `--product` flags to `swift build`; Swift 6.4 only honors the last one, so release builds were emitting only `tunedtwo-cli` and missing `TunedTwo`. Changed to separate `swift build --product TunedTwo` and `swift build --product tunedtwo-cli` invocations so both products are produced reliably across Swift 6.2+ and both native/swiftbuild build systems.

## 2026-11-05 — Removed source selector, sample file via env var

Removed the Source dropdown from the UI. Sample-file playback is now
triggered by `TUNEDTWO_SAMPLE_FILE`; when set, the app auto-starts and the
frequency line shows the file name. `TUNEDTWO_SMOKE_TEST` still controls the
self-terminating smoke-test report. The app bundle no longer includes
`sample.bin`; tests and the smoke-test script use the extracted
`Resources/sample.bin` directly.

## 2026-11-04 — HERE traffic and weather map tests

Added HERE ingest tests for `TrafficMap` and `WeatherMap`, plus per-tile
bounding-box reference data in `TrafficMapTests`.

## 2026-11-04 — CLI traffic-map handles HERE tiles

`traffic-map` now ingests dumped HERE tiles (`*_trafficMap_*.png`) and only
parses `TMI_*.txt` config files. Added `TrafficMap.parseHereTrafficName` and
`processHereImageFile(info:data:)`.

## 2026-11-04 — Added tuner coverage tests

Added headless smoke tests for `nameForDSDMIMEType`, `TunerSession`
init/teardown, and `Nrsc5Context` decoding the bundled `sample.bin`.
Fixed `SampleFileProvider`'s dev fallback for SwiftPM tests.

## 2026-11-04 — Raised minimum target to macOS 26

Bumped the deployment target and toolchain floor to match the host SDK and modern control behaviors.

## 2026-11-03 — Migrated to SwiftPM-first build

Replaced the XcodeGen-generated `.xcodeproj` with a root-level `Package.swift` and a `Makefile`/`build.sh` workflow modeled on [tqbf/swiftui-app](https://github.com/tqbf/swiftui-app).

The `libnrsc5` CMake build remains a Makefile pre-step. Making it native to SwiftPM is the next major follow-on.
