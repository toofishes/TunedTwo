This file captures non-obvious project conventions and gotchas that came up during development.

## Project navigation

- Start with [`PLAN.md`](PLAN.md) — it's the index to all project docs.
- Check [`PROGRESS.md`](PROGRESS.md) to see what changed recently.
- Build-system details are in [`plans/build-system.md`](plans/build-system.md).
- Architecture notes are in [`plans/architecture.md`](plans/architecture.md).

## Agent workflow and skills

- Keep [`PLAN.md`](PLAN.md) as the master documentation index; put depth in `plans/whatever.md` and record day-to-day work in [`PROGRESS.md`](PROGRESS.md).
- Keep [`PROGRESS.md`](PROGRESS.md) entries brief — one or two lines is usually enough.
- Before and after deciding on UI code, run the **swiftui-pro** skill to verify we're following modern SwiftUI best practices (see also [`SWIFTUI-RULES.md`](SWIFTUI-RULES.md)).
- When setting type, run the **typography-designer** skill to keep the type scale and hierarchy consistent.
- When designing macOS UI, run the **macos-design** skill to keep the app aligned with modern professional macOS idioms.
- Do not commit or push changes without asking the user first. You may open PRs, but you must never merge them to `main` yourself.

## Build system

Build-system details live in [`plans/build-system.md`](plans/build-system.md). The short version for day-to-day work:

- Use `make` as the front door: `make check`, `make test`, `make build`, `make run`, `make cli`.
- `Package.swift` is the source of truth; there is no `.xcodeproj` or `project.yml`.

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
- See [`plans/build-system.md`](plans/build-system.md) for how `libnrsc5.dylib` is built and linked.

## Git / submodules

- Do not commit or push changes without asking the user first.
- `Vendor/nrsc5/` is a Git submodule pointing at a separate repository (`toofishes/nrsc5`). Never push to the submodule repository or update the submodule pointer in the parent repo without explicit user approval.
