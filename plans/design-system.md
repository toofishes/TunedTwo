# Design system

The UI is governed by the skills referenced in [`AGENTS.md`](../AGENTS.md) and one
source of truth in code: [`Sources/TunedTwo/Theme.swift`](../Sources/TunedTwo/Theme.swift).

## The skills

- **macos-design** — layout, composition, native macOS idioms. Use before
deciding a design and when reviewing one.
- **typography-designer** — the type scale and hierarchy.
- **swiftui-pro** — modern-API/correctness review of the code.

Run them before *and* after writing UI.

## `Theme` — one place for type and metrics

Every font and layout constant lives in `Theme`. Two rules keep it honest
(`SWIFTUI-RULES.md` §2.4, §5.1):

1. **Scale is semantic.** Fonts come from SwiftUI text styles
(`.caption` → `.body` → `.title2` → `.largeTitle`), never hardcoded point
sizes, so Dynamic Type and OS metric updates keep working.
2. **Emphasis is weight; de-emphasis is color.** Headings get `.semibold`/
`.bold`; quieter text gets `.secondary`, never a lighter weight.

### The type scale

| Role | Style | Used by |
|------|-------|---------|
| App icon | `.largeTitle` bold | header SF Symbol |
| App title | `.title2` bold | header title |
| Section/row title | `.headline` | log-event titles |
| Body | `.body` | default body |
| Secondary body | `.subheadline` | log-event descriptions |
| Metadata | `.caption` | status bar, timestamps, counts |
| Emphasized metadata | `.caption` bold | count badges |

### Common metrics

| Constant | Value | Use |
|----------|-------|-----|
| `sectionSpacing` | 16 | major sections in a pane |
| `groupSpacing` | 12 | related groups within a section |
| `itemSpacing` | 10 | stacked items (traffic/weather panes) |
| `tightSpacing` | 8 | tightly related items (chip + label) |
| `defaultPadding` | 16 | window/pane edge padding |
| `cardCornerRadius` | 8 | card-style containers |
| `imageCornerRadius` | 12 | lot image thumbnails |
| `lotImageSize` | 100 | album-art / lot thumbnail |
| `logIconSize` | 32 | log-event row icon circle |
| `metadataLabelWidth` | 80 | fixed label column in metadata rows |
| `frequencyFieldWidth` | 120 | frequency text field |

## macOS idioms applied

- The app is a single-window utility built around a `TabView` — radio,
traffic, weather, and logs are top-level destinations.
- `ContentUnavailableView` is used for the no-data states in the traffic and
weather tabs (`SWIFTUI-RULES.md` §7.1).
- Light/dark mode come for free: views use system colors and materials
(`.secondary`, `.bar`, accent), not a custom palette.

When you restyle, change `Theme` first; if you're typing the same literal a
third time in a view, it belongs in `Theme`.
