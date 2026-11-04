# TunedTwo — Project Index

This is the master index for project documentation. For day-to-day work, read this first, then check [`PROGRESS.md`](PROGRESS.md) for what has happened recently.

## Quick start

```sh
make check   # fast compile gate
make test    # headless tests
make build   # build/TunedTwo.app + build/tunedtwo-cli
make run     # build and launch the app
make cli     # build the command-line tool
```

See the [`Makefile`](Makefile) for the full target list (`make help`).

## Documentation

- [`plans/swiftpm-migration-plan.md`](plans/swiftpm-migration-plan.md) — how and why we moved from XcodeGen to SwiftPM.
- [`plans/build-system.md`](plans/build-system.md) — how `Package.swift`, `Makefile`, and `build.sh` work together.
- [`plans/architecture.md`](plans/architecture.md) — targets, data flow, and how the pieces fit.
- [`plans/design-system.md`](plans/design-system.md) — the `Theme` type scale + metrics and the macOS idioms applied.
- [`plans/nrsc5-native-build.md`](plans/nrsc5-native-build.md) — *future* plan for making the C library build fully native inside SwiftPM.
- [`AGENTS.md`](AGENTS.md) — conventions for agents working in this repo.
- [`SWIFTUI-RULES.md`](SWIFTUI-RULES.md) — hard-won SwiftUI rules from the template this app is based on.
- [`PROGRESS.md`](PROGRESS.md) — running log of meaningful changes.
- [`PROBLEMS.md`](PROBLEMS.md) — hard-won, project-specific gotchas.

## Build system source of truth

- [`Package.swift`](Package.swift) — SwiftPM manifest: targets, dependencies, linker settings.
- [`Makefile`](Makefile) — front door for builds, tests, and releases.
- [`build.sh`](build.sh) — `swift build` → `.app` bundle + codesign.
- [`scripts/build-nrsc5.sh`](scripts/build-nrsc5.sh) — CMake build of the vendored `libnrsc5`.
- [`scripts/prepare-sample.sh`](scripts/prepare-sample.sh) — extract the bundled sample I/Q file.
- [`scripts/smoke-test.sh`](scripts/smoke-test.sh) — end-to-end smoke test of the app.

## Status

Migration to SwiftPM-first build is complete and verified. The follow-on item is making the `libnrsc5` C build native to SwiftPM; see [`plans/nrsc5-native-build.md`](plans/nrsc5-native-build.md) when that work starts.
