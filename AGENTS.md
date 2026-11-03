This file captures non-obvious project conventions and gotchas that came up during development.

## Project navigation

- Start with [`PLAN.md`](PLAN.md) — it's the index to all project docs.
- Check [`PROGRESS.md`](PROGRESS.md) to see what changed recently.
- Build-system details are in [`plans/build-system.md`](plans/build-system.md).
- Architecture notes are in [`plans/architecture.md`](plans/architecture.md).

## Build system

- **`Package.swift` is the source of truth.** There is no `.xcodeproj` or `project.yml`.
- Use `make` as the front door: `make check`, `make test`, `make build`, `make run`, `make cli`.
- The vendored `libnrsc5` dynamic library is built by `scripts/build-nrsc5.sh` before Swift compilation.
- `build.sh` assembles `build/TunedTwo.app` and `build/tunedtwo-cli` and handles codesigning.

## Code linting and formatting

- Run `make format` (or `swift format -r -i Tests Sources`) from the root of the repo.

## Concurrency and `Sendable`

- This project uses Swift 6 strict concurrency. Do not reach for `@unchecked Sendable` as a default escape hatch.
- Many SDK types that were historically not considered `Sendable` (for example, `CGImage`) are now `Sendable` on modern Apple SDKs. Verify the current SDK behavior with the compiler rather than assuming older knowledge.
- If a type must cross isolation boundaries, make it genuinely `Sendable` by ensuring its stored properties are `Sendable`. Only introduce `@unchecked Sendable` after explicit discussion and approval.

## CLI (`Sources/TunedTwoCLI`)

- The CLI uses Apple's `swift-argument-parser`.
- A small custom `@main` entry point is kept so runtime failures exit with code `2`, while argument-parser usage errors exit with the standard `64` (`EX_USAGE`).
- The command struct is named `TrafficMapCommand`, not `TrafficMap`, to avoid shadowing the `TrafficMap` model type from `TunedTwoCore`.
- `ParsableCommand` conformers must use `static let configuration` under Swift 6 strict concurrency; `static var` produces a concurrency-safety error.

## C library (`CNrsc5`)

- `Sources/CNrsc5/` is a SwiftPM `systemLibrary` target exposing `Vendor/nrsc5/include/nrsc5.h`.
- Import it as `import CNrsc5` in `TunedTwoCore`.
- Linker settings for the prebuilt `libnrsc5.dylib` are duplicated in `Package.swift` on every target that needs them because SwiftPM does not propagate `unsafeFlags` across target boundaries.
