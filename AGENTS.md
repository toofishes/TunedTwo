This file captures non-obvious project conventions and gotchas that came up during development.

## Project generation

- `project.yml` is the source of truth. The checked-in `TunedTwo.xcodeproj` is a generated artifact.
- Regenerate the project after any `project.yml` change:
  ```bash
  xcodegen generate
  ```
- The project uses Xcode 16 file-system synchronized groups (folders) instead of traditional groups to keep `project.pbxproj` diffs small. This is configured in `project.yml` with:
  ```yaml
  options:
    defaultSourceDirectoryType: syncedFolder
  ```
  Note: XcodeGen emits **per-target synced folders** (`Sources/TunedTwo`, `Sources/TunedTwoCLI`, `Sources/TunedTwoCore`, etc.) rather than a single `Sources` synced folder with target exception sets. If the checked-in `.xcodeproj` ever differs from this, it was likely hand-edited in Xcode.

## Code linting and formatting

- Run `swift format -r -i Tests Sources` from the root of the repo to ensure code matches expecting formatting standards.

## Concurrency and `Sendable`

- This project uses Swift 6 strict concurrency. Do not reach for `@unchecked Sendable` as a default escape hatch.
- Many SDK types that were historically not considered `Sendable` (for example, `CGImage`) are now `Sendable` on modern Apple SDKs. Verify the current SDK behavior with the compiler rather than assuming older knowledge.
- If a type must cross isolation boundaries, make it genuinely `Sendable` by ensuring its stored properties are `Sendable`. Only introduce `@unchecked Sendable` after explicit discussion and approval.

## CLI (`Sources/TunedTwoCLI`)

- The CLI uses Apple's `swift-argument-parser`. The hand-rolled parser was removed.
- A small custom `@main` entry point is kept so runtime failures exit with code `2`, while argument-parser usage errors exit with the standard `64` (`EX_USAGE`).
- The command struct is named `TrafficMapCommand`, not `TrafficMap`, to avoid shadowing the `TrafficMap` model type from `TunedTwoCore`.
- `ParsableCommand` conformers must use `static let configuration` under Swift 6 strict concurrency; `static var` produces a concurrency-safety error.
