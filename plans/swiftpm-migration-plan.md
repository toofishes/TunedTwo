# Migration Plan: XcodeGen → SwiftPM-First Build

## Goal

Move TunedTwo from an XcodeGen-generated `.xcodeproj` to a root-level `Package.swift` as the single source of truth, heavily modeled on [tqbf/swiftui-app](https://github.com/tqbf/swiftui-app). The result should be:

- No checked-in `TunedTwo.xcodeproj` or `project.yml`.
- `swift build`, `swift test`, and a Makefile as the primary agent/CLI interface.
- Xcode only as a toolchain/SwiftUI preview host, opened via **File → Open Package**.
- The existing C (`libnrsc5`) dependency continues to work, built by the existing CMake script.
- A clear follow-on phase for making the C library build fully native inside SwiftPM and eliminating the Homebrew build-time dependency.

## What we will not change

- Swift 6 strict concurrency.
- `swift-format` configuration and formatting conventions.
- The `Vendor/nrsc5` Git submodule.
- macOS 15 deployment target (SwiftPM tools version 6.2).
- The core app/CLI/test source layout under `Sources/` and `Tests/`.

## Target repository layout

```text
.
├── Package.swift                 # source of truth for targets, deps, and linker flags
├── Makefile                      # front door: check / test / build / run / cli / dist
├── build.sh                      # swift build → .app bundle + codesign (driven by Makefile)
├── VERSION                       # fallback release version (git tag wins)
├── README.md                     # rewritten for SwiftPM workflow
├── AGENTS.md                     # updated conventions for agents
├── PLAN.md                       # master doc index (new)
├── PROGRESS.md                   # running log (new)
├── PROBLEMS.md                   # project-specific gotchas (new)
├── .github/workflows/build.yml   # CI gate: make check && make test
├── .gitignore                    # ignore .xcodeproj, .build, build/, dist/
├── Resources/
│   ├── Info.plist                # app metadata with __VERSION__ placeholders
│   ├── sample.bin                # generated from Vendor/nrsc5/support/sample.xz
│   ├── traffic_sample/           # existing test data
│   └── weather_sample/           # existing test data
├── TunedTwo/
│   └── TunedTwo.entitlements     # sandbox / hardened-runtime entitlements
├── Sources/
│   ├── CNrsc5/                   # SwiftPM system-library wrapper for libnrsc5
│   │   ├── module.modulemap
│   │   └── shim.h
│   ├── TunedTwo/                 # the SwiftUI app
│   ├── TunedTwoCLI/              # the command-line tool
│   └── TunedTwoCore/             # shared library
├── Tests/
│   └── TunedTwoTests/            # swift-testing suite, no app host
├── scripts/
│   ├── build-nrsc5.sh            # existing CMake build (kept)
│   ├── prepare-sample.sh         # existing sample extraction (kept)
│   ├── smoke-test.sh             # updated to use new build output
│   └── make-icon.swift           # optional icon generator (template convention)
├── Vendor/
│   └── nrsc5/                    # git submodule
└── build.sh                      # swift build → .app bundle + codesign (repo root, like the template)
```

## Phase 1 — Create the SwiftPM manifest

### 1.1 Add `Package.swift`

Create a root manifest with these targets:

| Target | Type | Purpose |
|--------|------|---------|
| `CNrsc5` | `systemLibrary` | Exposes `Vendor/nrsc5/include/nrsc5.h` to Swift via a shim header/module map. |
| `TunedTwoCore` | `target` | Shared core library; depends on `CNrsc5` and `swift-collections`. |
| `TunedTwo` | `executableTarget` | SwiftUI app; depends on `TunedTwoCore`. |
| `TunedTwoCLI` | `executableTarget` | Command-line tool; depends on `TunedTwoCore`, `swift-argument-parser`, `GRDB`. |
| `TunedTwoTests` | `testTarget` | Headless tests; depends on `TunedTwoCore`. |

Products:

- `.executable(name: "TunedTwo", targets: ["TunedTwo"])`
- `.executable(name: "tunedtwo-cli", targets: ["TunedTwoCLI"])`

Dependencies to carry over from `project.yml`:

- `swift-argument-parser` (from 1.8.2)
- `swift-collections` (from 1.7.4)
- `GRDB.swift` (from 7.11.1)

### 1.2 C-wrapper target `Sources/CNrsc5`

Create:

- `Sources/CNrsc5/module.modulemap`
- `Sources/CNrsc5/shim.h`

```text
module CNrsc5 [system] {
    header "shim.h"
    link "nrsc5"
    export *
}
```

`shim.h`:

```c
#include "../../Vendor/nrsc5/include/nrsc5.h"
```

Then replace `import nrsc5` with `import CNrsc5` in `Sources/TunedTwoCore/**/*.swift`.

Rationale: this is the standard SwiftPM pattern for a vendored C library that is not built by SwiftPM itself. The actual `libnrsc5.dylib` is supplied by `scripts/build-nrsc5.sh` and located at link time with `unsafeFlags`.

### 1.3 Linker settings for the prebuilt `libnrsc5.dylib`

Because `unsafeFlags` are **not** propagated across target boundaries, every target that ultimately links `libnrsc5` needs the search path. Define a shared helper in `Package.swift`:

```swift
let nrsc5LinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-L", "Vendor/nrsc5/build/src"]),
    .linkedLibrary("nrsc5"),
]
```

Apply it to `TunedTwoCore`, `TunedTwo`, `TunedTwoCLI`, and `TunedTwoTests`.

The dylib is already built with an `@rpath/libnrsc5.dylib` install name, so the executables only need an rpath that points to wherever we embed it (handled by `build.sh`, see Phase 3). For local `swift run` and `swift test`, add an additional rpath to `Vendor/nrsc5/build/src` (absolute or `@loader_path`-relative) so the binaries can find the library before `build.sh` has copied anything.

### 1.4 Clean up generated Xcode artifacts

- `git rm -r TunedTwo.xcodeproj`
- `git rm project.yml`
- Remove or ignore `DerivedData/`.
- Update `.gitignore`:
  - add `*.xcodeproj/`, `*.xcworkspace/`, `.build/`, `.swiftpm/`, `build/`, `dist/`, `DerivedData/`
  - remove the `*.entitlements` ignore so `TunedTwo/TunedTwo.entitlements` can be checked in

## Phase 2 — Build tooling (Makefile + build.sh)

### 2.1 Port/adapt the template Makefile

Primary targets:

- `make` / `make build` → assemble `build/TunedTwo.app`
- `make check` → `swift build -c debug` (compile-only gate, no bundling)
- `make test` → `swift test`
- `make run` → build + `open build/TunedTwo.app`
- `make cli` → build `tunedtwo-cli` and copy to `build/tunedtwo-cli`
- `make icon` → regenerate `build/AppIcon.icns` (optional; can start without an icon)
- `make clean` → remove `build/`, `.build/`, `dist/`
- `make deps` → verify macOS/Swift toolchain and that `Vendor/nrsc5` is initialized
- `make dist` → release pipeline (sign → notarize → staple → zip) once certs are configured
- `make format` → `swift format -r -i Tests Sources`

### 2.2 Port/adapt `build.sh`

`build.sh` does what Xcode used to do:

1. Run `swift build -c $CONFIG`.
2. Locate the built executables (`TunedTwo`, `TunedTwoCLI`) via `--show-bin-path`.
3. Assemble `build/TunedTwo.app`:
   - `Contents/MacOS/TunedTwo`
   - `Contents/Info.plist` from `Resources/Info.plist` with `__SHORT_VERSION__` / `__BUILD_VERSION__` replaced
   - `Contents/PkgInfo`
   - `Contents/Resources/AppIcon.icns` if present
   - `Contents/Resources/sample.bin`
   - any `*.bundle` emitted by SwiftPM dependencies (e.g. GRDB resources)
   - (Do **not** copy `traffic_sample/` or `weather_sample/` into the app bundle; they are test/CLI data, not app runtime resources.)
   - `Contents/Frameworks/libnrsc5.dylib`
4. Copy `tunedtwo-cli` to `build/tunedtwo-cli` and place `libnrsc5.dylib` beside it.
5. Set rpaths and codesign (ad-hoc by default, real identity for `make dist`).

`build.sh` should be idempotent and safe to run from a clean tree.

### 2.3 Entitlements and Info.plist

Create:

- `TunedTwo/TunedTwo.entitlements` — start from the template's sandboxed entitlements and add any hardened-runtime exceptions the app currently needs (e.g. `com.apple.security.device.usb` if RTL-SDR access requires it).
- `Resources/Info.plist` — copy relevant keys from the generated `Info.plist` (bundle ID, category, copyright, principal class, etc.) with version placeholders.

### 2.4 Wire the existing helper scripts

- `scripts/build-nrsc5.sh` is invoked by the Makefile before any target that links code (e.g. as a dependency of `build` and `check`). It is already idempotent; add a make rule that short-circuits when `Vendor/nrsc5/build/src/libnrsc5.dylib` is newer than the source tree.
- `scripts/prepare-sample.sh` is invoked by `build.sh` before copying resources into the app bundle.
- `scripts/smoke-test.sh` is updated to:
  - run `make build` if needed,
  - launch `build/TunedTwo.app/Contents/MacOS/TunedTwo` with `TUNEDTWO_SMOKE_TEST=1`.

## Phase 3 — Runtime wiring for `libnrsc5.dylib`

The prebuilt dylib currently depends only on system frameworks, which is great. We still have to make sure every binary can find it.

| Binary | Where `libnrsc5.dylib` lives | Rpath needed |
|--------|------------------------------|--------------|
| `build/TunedTwo.app/Contents/MacOS/TunedTwo` | `Contents/Frameworks/libnrsc5.dylib` | `@executable_path/../Frameworks` |
| `build/tunedtwo-cli` | next to the executable | `@executable_path` |
| `.build/debug/TunedTwoCLI` (for `swift run`) | found in repo tree | absolute or `@loader_path`-relative path to `Vendor/nrsc5/build/src` |
| `.build/debug/*Tests.xctest` (for `swift test`) | found in repo tree | absolute or `@loader_path`-relative path to `Vendor/nrsc5/build/src` |

Add the appropriate rpath at link time with target-specific `unsafeFlags`, e.g. for the app:

```swift
.unsafeFlags(["-Wl,-rpath,@executable_path/../Frameworks"])
```

for the CLI:

```swift
.unsafeFlags(["-Wl,-rpath,@executable_path"])
```

and for tests / `swift run` an extra rpath to the build tree (absolute paths are acceptable here because these binaries are never shipped):

```swift
.unsafeFlags(["-Wl,-rpath,VENDOR_NRSC5_BUILD_SRC"])
```

Use `Context.packageDirectory` or a hardcoded relative path to derive `VENDOR_NRSC5_BUILD_SRC` at manifest-evaluation time.

`build.sh` should:

1. Copy `Vendor/nrsc5/build/src/libnrsc5.dylib` into the app bundle's `Contents/Frameworks`.
2. Copy the CLI executable and `libnrsc5.dylib` side-by-side into `build/`.
3. Run `install_name_tool -add_rpath …` only if the rpath is not already present (belt-and-suspenders).
4. Codesign everything after modification.

## Phase 4 — Verification checklist

Before declaring Phase 1–3 done, the following must pass:

- [ ] `make check` compiles all targets without errors.
- [ ] `make test` passes.
- [ ] `make build` produces `build/TunedTwo.app`.
- [ ] `make run` launches the app and the sample-file playback works.
- [ ] `make cli` produces `build/tunedtwo-cli` and:
  - `build/tunedtwo-cli traffic-map Resources/traffic_sample -o /tmp/out.png` succeeds.
  - `build/tunedtwo-cli --help` works.
- [ ] `scripts/smoke-test.sh` passes.
- [ ] `otool -L build/TunedTwo.app/Contents/MacOS/TunedTwo` shows `@rpath/libnrsc5.dylib` and no Homebrew paths.
- [ ] `otool -L build/tunedtwo-cli` shows `@rpath/libnrsc5.dylib`.
- [ ] The app bundle can be moved to `/Applications/` and still launches.

## Phase 5 — Documentation and agent/CI tooling

Port the template's documentation conventions, adapted for an existing project:

- `PLAN.md` — master index pointing to `plans/*.md`, `PROGRESS.md`, `PROBLEMS.md`.
- `PROGRESS.md` — start a running log with the migration as the first entry.
- `PROBLEMS.md` — migrate project-specific lessons from `AGENTS.md` and future gotchas.
- `plans/build-system.md` — how `Package.swift`, `Makefile`, and `build.sh` fit together.
- `plans/architecture.md` — current target graph and data flow.
- Update `README.md` for the SwiftPM workflow (remove XcodeGen instructions, add `make check` / `make run`).
- Update `AGENTS.md` to reference the new build conventions and doc index.
- Add `.github/workflows/build.yml` that runs on `macos-15`, caches `.build`, and runs `make check && make test`.

Optional but recommended later: a `SWIFTUI-RULES.md` crib sheet for UI work, if the project accumulates enough SwiftUI-specific rules to justify it.

## Phase 6 — Follow-on: native C-library build (not part of this migration)

The plan above keeps `scripts/build-nrsc5.sh` (CMake) as a pre-build step. This preserves the status quo while everything else moves to SwiftPM. The next major improvement is to make `libnrsc5` buildable by SwiftPM itself, removing the Homebrew build-time dependency (`cmake`, `libtool`, `pkg-config`) and making `swift build` fully self-contained.

Candidate approaches, in rough order of invasiveness:

1. **SwiftPM build-tool plugin** — keep CMake, but invoke `scripts/build-nrsc5.sh` automatically during `swift build`. Does not eliminate Homebrew, but removes the need for a separate Makefile step.
2. **XCFramework binary target** — build `libnrsc5.dylib` + header into an XCFramework (e.g. in CI) and consume it via `.binaryTarget`. Clean for SwiftPM, but still needs a build environment somewhere.
3. **SwiftPM C target from submodule sources** — add a `.target` that compiles the `nrsc5` C sources directly. The hard part is its dependencies (`faad2`, `fftw`, `libusb`, `rtlsdr`), which today are built by CMake `ExternalProject`. This would likely require either:
   - vendoring/breaking out each dependency as its own SwiftPM C target, or
   - prebuilding a static `libnrsc5.a` that statically links all deps and consuming that as a binary target.

The current `build-nrsc5.sh` already builds the dependencies from source with `USE_SYSTEM_*=OFF`, so the runtime is already Homebrew-free. The follow-on is therefore about build-time self-containment, not runtime linking.

Record the chosen approach in `plans/nrsc5-native-build.md` when work starts.

## Sanity notes / open questions

- **C-wrapper module name**: This plan uses `CNrsc5`. If you prefer to keep `import nrsc5`, name the target/directory `nrsc5` and the module map module `nrsc5` instead. `CNrsc5` follows SwiftPM convention and avoids a generic name colliding with the actual library.
- **Resource placement**: Keeping `traffic_sample/` and `weather_sample/` at `Resources/` avoids rewriting test path logic. If we later move them into `TunedTwoCore/Resources` as SwiftPM resources, tests must switch to `Bundle.module`. Decide at implementation time; the rest of the plan is independent.
- **Sandbox / entitlements**: The current Xcode project enables hardened runtime and App Sandbox. The new entitlements file must preserve whatever capabilities the RTL-SDR code path needs. Verify with a live RTL-SDR test after the migration.
- **GRDB resources**: `build.sh` already copies `*.bundle`; verify GRDB does not need additional linker flags (e.g. `-lsqlite3`). Add `.linkedLibrary("sqlite3")` to `TunedTwoCLI` if linking fails.
- **Access levels**: `TunedTwoCore` is now a real SwiftPM library target. Anything used by `TunedTwo` or `TunedTwoCLI` must be `public` (or `@testable import` in tests). Audit `Sources/TunedTwoCore` for missing `public`.
- **Xcode workflow**: With no `.xcodeproj`, opening the repo in Xcode is **File → Open Package**. SwiftUI previews and breakpoints still work; the project is transient.

## Appendix — proposed `Package.swift` skeleton

```swift
// swift-tools-version: 6.2
import PackageDescription

let nrsc5BuildTreePath = "\(Context.packageDirectory)/Vendor/nrsc5/build/src"
let nrsc5LinkerSettings: [LinkerSetting] = [
    .unsafeFlags(["-L", "Vendor/nrsc5/build/src"]),
    .linkedLibrary("nrsc5"),
]
let nrsc5BuildTreeRpath: [LinkerSetting] = [
    .unsafeFlags(["-Wl,-rpath,\(nrsc5BuildTreePath)"]),
]

let package = Package(
    name: "TunedTwo",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "TunedTwo", targets: ["TunedTwo"]),
        .executable(name: "tunedtwo-cli", targets: ["TunedTwoCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.7.4"),
        .package(url: "https://github.com/groue/grdb.swift", from: "7.11.1"),
    ],
    targets: [
        .systemLibrary(name: "CNrsc5"),

        .target(
            name: "TunedTwoCore",
            dependencies: [
                "CNrsc5",
                .product(name: "Collections", package: "swift-collections"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: nrsc5LinkerSettings
        ),

        .executableTarget(
            name: "TunedTwo",
            dependencies: ["TunedTwoCore"],
            path: "Sources/TunedTwo",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: nrsc5LinkerSettings + nrsc5BuildTreeRpath + [
                .unsafeFlags(["-Wl,-rpath,@executable_path/../Frameworks"]),
            ]
        ),

        .executableTarget(
            name: "TunedTwoCLI",
            dependencies: [
                "TunedTwoCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/TunedTwoCLI",
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: nrsc5LinkerSettings + nrsc5BuildTreeRpath + [
                .unsafeFlags(["-Wl,-rpath,@executable_path"]),
            ]
        ),

        .testTarget(
            name: "TunedTwoTests",
            dependencies: ["TunedTwoCore"],
            path: "Tests/TunedTwoTests",
            linkerSettings: nrsc5LinkerSettings + nrsc5BuildTreeRpath
        ),
    ]
)
```

This is a starting point; exact settings may shift during implementation.

---

## Appendix B — Notes for a fresh session

Read this section if you are picking up this plan in a new terminal/agent session before building.

### Current repo state (as of when this plan was written)

- `TunedTwo.xcodeproj/project.pbxproj` and `Vendor/nrsc5` show as modified in `git status`. These changes are from normal development and the submodule build; they are **not** part of the migration. Commit, stash, or discard them before beginning the migration so the diff stays clean.
- `DerivedData/` exists locally and is gitignored; it can simply be deleted once the Xcode project is gone.

### Prerequisites assumed by this plan

- macOS 15 host (or newer).
- Xcode 16 / Swift 6 toolchain (`swift --version` should report 6.x).
- `git` and standard macOS CLI tools.
- Homebrew-installed build tools: `cmake`, `libtool`, `pkg-config`. These are still needed to run `scripts/build-nrsc5.sh` in Phase 1–5.
- `xz` (usually present via macOS or Homebrew) for `scripts/prepare-sample.sh`.
- Optional: `swift-format` for `make format`.

### First-time setup before building

```sh
git submodule update --init --recursive   # ensure Vendor/nrsc5 is populated
make deps                                  # verify toolchain and nrsc5 submodule
scripts/build-nrsc5.sh                    # prebuild libnrsc5.dylib
```

The rest of the migration can then be driven by `make check`, `make test`, and `make build`.

### If `swift build` cannot find `libnrsc5`

1. Confirm the dylib exists: `ls Vendor/nrsc5/build/src/libnrsc5.dylib`.
2. Confirm its install name is `@rpath/libnrsc5.dylib`: `otool -D Vendor/nrsc5/build/src/libnrsc5.dylib`.
3. Confirm the `Package.swift` rpath flags point to a valid path for the binary being run:
   - `otool -l build/TunedTwo.app/Contents/MacOS/TunedTwo | grep -A2 LC_RPATH`
   - `otool -l .build/debug/TunedTwoCLI | grep -A2 LC_RPATH`
4. If `swift test` fails to load the dylib, the test executable’s rpath is the most likely culprit; add or correct the absolute/`@loader_path`-relative rpath to `Vendor/nrsc5/build/src`.

### If `make run` launches but audio/metadata does not work

- Check that `build.sh` ran `scripts/prepare-sample.sh` and copied `Resources/sample.bin` into `build/TunedTwo.app/Contents/Resources/`.
- Check Console or the smoke-test log for sandbox denials; the new entitlements file may need additional capabilities compared with the old Xcode target.

### Recovering the old Xcode-based build

The migration intentionally removes `project.yml` and `TunedTwo.xcodeproj/` from the repo. If you need to roll back:

```sh
git checkout HEAD -- project.yml TunedTwo.xcodeproj
xcodegen generate
```

Do this on a branch; once the SwiftPM build is verified on `main`, the old files can be permanently deleted.

### Reference commands after migration

```sh
make check       # fast compile gate
make test        # run headless tests
make build       # produce build/TunedTwo.app
make run         # build and launch the app
make cli         # produce build/tunedtwo-cli
make clean       # reset build artifacts
make dist        # release pipeline (needs signing identity + git tag)
```

### When to move on to Phase 6 (native C build)

Only after Phase 4’s verification checklist is fully green *and* the repo has been used for a few normal development cycles. Phase 6 is a larger, riskier change that should have its own plan document (`plans/nrsc5-native-build.md`) before work starts.
