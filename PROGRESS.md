# Progress

Running log of meaningful changes. Newest first.

---

## 2026-11-03 — Migrated to SwiftPM-first build

Replaced the XcodeGen-generated `.xcodeproj` with a root-level `Package.swift` and a `Makefile`/`build.sh` workflow modeled on [tqbf/swiftui-app](https://github.com/tqbf/swiftui-app).

What changed:
- Added `Package.swift` with SwiftPM tools 6.2, macOS 15 target, and targets for `TunedTwo`, `TunedTwoCLI`, `TunedTwoCore`, `TunedTwoTests`, and the `CNrsc5` system-library wrapper.
- Created `Sources/CNrsc5/` to expose `Vendor/nrsc5/include/nrsc5.h` to Swift.
- Added `Makefile`, `build.sh`, `Resources/Info.plist`, `TunedTwo/TunedTwo.entitlements`, and `scripts/make-icon.swift`.
- Removed `project.yml`, `TunedTwo.xcodeproj/`, and local `DerivedData/`.
- Updated `scripts/smoke-test.sh` to use the new `build/TunedTwo.app` path.
- Added `VERSION`, `.github/workflows/build.yml`, `PLAN.md`, `PROGRESS.md`, `PROBLEMS.md`, and `plans/{build-system,architecture}.md`.
- Updated `README.md` and `AGENTS.md` for the new workflow.

Verification:
- `make check` ✓
- `make test` ✓ (55 tests)
- `make build` ✓
- `make run` launches the app ✓
- `make cli` produces a working `tunedtwo-cli` ✓
- `scripts/smoke-test.sh` passes end-to-end ✓

The `libnrsc5` CMake build remains a Makefile pre-step. Making it native to SwiftPM is the next major follow-on.
