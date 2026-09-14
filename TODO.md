# TunedTwo TODO / loose ends

## Now (MVP – audio + simple UI)

- [x] Vendor `nrsc5` as a Git submodule and build it as a dynamic library.
- [x] Clean up duplicate reference checkouts.
- [x] Create XcodeGen-based native macOS app project.
- [x] Create SwiftUI views: frequency, program/subchannel, play/stop, status.
- [x] Implement `TunerSession` wrapper around `libnrsc5`:
  - [x] C callback trampoline.
  - [x] File playback (`nrsc5_open_file`).
  - [x] RTL-SDR playback (`nrsc5_open` + `set_frequency`).
  - [x] Program switching (client-side filter of audio/ID3 events).
- [x] Implement `AudioPlayer` using `AVAudioEngine` + `AVAudioPlayerNode`.
- [x] Basic metadata model: station name, slogan, title/artist, MER/BER.
- [x] Sample-file extraction build phase / runtime helper.
- [x] Compile and run smoke test from sample file.

## Next (metadata & UX polish)

- [ ] Display SIG service list and active data services.
- [ ] Live signal quality gauges (MER lower/upper, BER).
- [ ] Persist user settings (frequency, program, last window frame).
- [ ] Better native macOS chrome: menu bar items, keyboard shortcuts, toolbar.
- [ ] App icon and asset catalog.
- [ ] Proper entitlements / code signing for USB access (RTL-SDR).

## Later (advanced features from nrsc5-studio)

- [ ] Album art / station logo (LOT image decode).
- [ ] Traffic map / weather radar (HERE images).
- [ ] 24-hour song log + CSV export.
- [ ] Spectrum / waterfall visualization.
- [ ] QPSK constellation plot.
- [ ] Presets.
- [ ] Analog FM fallback (would require own FM demod or upstream support).

## Engineering / build

- [ ] Evaluate linking statically vs. dynamically. Currently dynamic per request; the dylib is copied into the app bundle.
- [ ] Bundle or document runtime dependencies (`libfftw3f`, `librtlsdr`) for distribution.
- [ ] Add a minimal XCTest smoke test target that verifies `libnrsc5` loads and decodes a sample to PCM.
- [ ] Swift concurrency: currently targeting Swift 5 mode; revisit strict concurrency once the callback/threading story is cleaner.
- [ ] Decide on a persistence strategy (`@AppStorage`, `UserDefaults`, or a small JSON file).
