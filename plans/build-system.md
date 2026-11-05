# Build system

No Xcode project, no `xcodebuild`, no XcodeGen. `swift build` compiles; `build.sh` bundles and signs; `make` orchestrates. Xcode is only a toolchain provider (`swift`, `codesign`, `notarytool`).

## The pieces

- **`Package.swift`** — SwiftPM manifest. Defines the `CNrsc5` system-library wrapper, the `TunedTwoCore` library, the `TunedTwo` app executable, the `TunedTwoCLI` executable, and the `TunedTwoTests` test target. Also carries the `-L` and rpath flags needed to link the prebuilt `libnrsc5.dylib`.
- **`Makefile`** — the front door. `make help` lists everything.
- **`build.sh`** — `swift build` → assemble `build/TunedTwo.app` (Info.plist with version placeholders, PkgInfo, icon, dependency bundles, `libnrsc5.dylib`) → copy `build/tunedtwo-cli` → codesign. Falls back to ad-hoc signing (`-`) when no real identity is available.
- **`Resources/Info.plist`** — bundle metadata. Version strings are placeholders filled at build time.
- **`TunedTwo/TunedTwo.entitlements`** — hardened-runtime exceptions for loading the locally-built `libnrsc5.dylib`.

## C library wiring

`libnrsc5` is vendored as a Git submodule under `Vendor/nrsc5` and built by `scripts/build-nrsc5.sh` (CMake). The resulting dylib has an `@rpath/libnrsc5.dylib` install name and depends only on system frameworks.

SwiftPM sees the C API through the `CNrsc5` system-library target, which exposes `Vendor/nrsc5/include/nrsc5.h` via a shim header and module map. Linking is done with explicit `unsafeFlags` for the library search path and rpath; these flags are duplicated on every target that needs them because SwiftPM does not propagate `unsafeFlags` across target boundaries.

## Everyday targets

| Target | What it does |
|--------|-------------|
| `make check` | `swift build` only — fast compile gate for CI/agents |
| `make test` | `swift test` |
| `make build` | `build/TunedTwo.app` + `build/tunedtwo-cli` |
| `make run` | build and `open` the app |
| `make cli` | build `build/tunedtwo-cli` |
| `make icon` | regenerate `build/AppIcon.icns` |
| `make clean` | remove `build/`, `.build/`, `dist/` |
| `make format` | run `swift-format` on `Sources/` and `Tests/` |

## Versioning

`make` resolves the version in this order: a `VERSION=` override → an exact `vX.Y.Z` git tag at HEAD → the `VERSION` file. `make print-version` shows what resolved and from where.

## Release pipeline (`make dist`)

Requires an exact `vX.Y.Z` tag at HEAD and a Developer ID signing identity. The chain is intentionally ordered:

```
clean → release → sign → zip-notary → notarize → staple → zip-release → checksum → verify-release
```

The two-zip dance is intentional: Apple's notary service takes a zip; stapling writes the ticket back into the `.app`; the zip you actually ship must be made **after** stapling. One-time credential setup:

```sh
make notary-setup TEAM_ID=XXXXXXXXXX APPLE_ID=you@example.com
```

`make github-release` uploads the release zip + `.sha256` to a GitHub release.

## CI gate

The minimum a change must pass: `make check && make test`. The minimum a *UI* change must pass: also `make run` and look at it.
