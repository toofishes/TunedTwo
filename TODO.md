# TunedTwo TODO / loose ends

## Next (metadata & UX polish)

- [ ] Display SIG service list and active data services.
- [x] Live signal quality gauges (MER lower/upper, BER).
- [ ] Persist user settings (frequency, program, last window frame).
- [ ] Better native macOS chrome: menu bar items, keyboard shortcuts, toolbar.
- [ ] App icon and asset catalog.
- [ ] Proper entitlements / code signing for USB access (RTL-SDR).

## Later (advanced features from nrsc5-studio)

- [ ] 24-hour song log + CSV export.
- [ ] Spectrum / waterfall visualization.
- [ ] QPSK constellation plot.
- [ ] Presets.
- [ ] Analog FM fallback (would require own FM demod or upstream support).

## Engineering / build

- [ ] Evaluate linking statically vs. dynamically. Currently dynamic per request; the dylib is copied into the app bundle.
- [ ] Bundle or document runtime dependencies (`libfftw3f`, `librtlsdr`) for distribution.
- [ ] Add a headless decoder test to the test bundle (libnrsc5 loads and decodes the sample to PCM) — now possible since `TunerSession` lives in `TunedTwoCore`.
- [x] Swift 6 strict concurrency: `TunerSession`/`AudioPlayer` are actors, C callback events flow through an `AsyncStream`, UI state is `@MainActor` and only reached via an awaited event sink. No `@unchecked Sendable` anywhere.
- [ ] Decide on a persistence strategy (`@AppStorage`, `UserDefaults`, or a small JSON file).
