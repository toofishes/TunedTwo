# Notes for future agents

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

## Swift Package dependencies

- `swift-argument-parser` is linked **only** to the `tunedtwo-cli` target. `TunedTwoCore` and `TunedTwo` must not depend on it.
- The package name is `swift-argument-parser`, but the linked product is `ArgumentParser`. In `project.yml`:
  ```yaml
  packages:
    swift-argument-parser:
      url: https://github.com/apple/swift-argument-parser
      from: 1.8.2
  targets:
    tunedtwo-cli:
      dependencies:
        - package: swift-argument-parser
          product: ArgumentParser
  ```
- `.gitignore` excludes `Package.resolved`, so the resolved version is not committed. Pin the desired minimum version in `project.yml`.

## CLI (`Sources/TunedTwoCLI`)

- The CLI uses Apple's `swift-argument-parser`. The hand-rolled parser was removed.
- A small custom `@main` entry point is kept so runtime failures exit with code `2`, while argument-parser usage errors exit with the standard `64` (`EX_USAGE`).
- The command struct is named `TrafficMapCommand`, not `TrafficMap`, to avoid shadowing the `TrafficMap` model type from `TunedTwoCore`.
- `ParsableCommand` conformers must use `static let configuration` under Swift 6 strict concurrency; `static var` produces a concurrency-safety error.
