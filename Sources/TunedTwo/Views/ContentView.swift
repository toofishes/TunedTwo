//
//  ContentView.swift
//  TunedTwo
//
//  Main SwiftUI view.
//

import SwiftUI

struct ContentView: View {
    @State private var state = TunerState()
    @State private var session: TunerSession?
    @State private var retuneTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            header
            controls
            Divider()
            metadata
            Divider()
            EventLogView(events: state.logEntries)
            Spacer()
            statusBar
        }
        .padding()
        .frame(minWidth: 480, minHeight: 440)
        .onChange(of: state.program) { _, newProgram in
            guard let session else { return }
            Task { await session.setProgram(newProgram) }
        }
        .onChange(of: state.frequencyMHz) { _, _ in
            scheduleRetune()
        }
        .onChange(of: state.isPlaying) { _, playing in
            if !playing {
                // Sessions that are no longer playing can't produce more
                // audio; dropping the reference lets the session's deinit
                // perform any remaining teardown.
                session = nil
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["TUNEDTWO_SMOKE_TEST"] == "1" {
                Task { await runSmokeTest() }
            }
        }
        .onDisappear {
            retuneTask?.cancel()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "radio")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
                Text("TunedTwo")
                    .font(.title2.bold())
                Text("Native macOS HD Radio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var controls: some View {
        Form {
            Section {
                Picker("Source", selection: $state.source) {
                    ForEach(TunerState.Source.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Frequency")
                    TextField("MHz", text: $state.frequencyMHz)
                        .textFieldStyle(.roundedBorder)
                        .disabled(state.source == .sampleFile)
                        .frame(width: 80)
                    Text("MHz")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Program")
                    Picker("Program", selection: $state.program) {
                        ForEach(0..<8) { i in
                            Text("HD\(i + 1)").tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            HStack {
                Spacer()
                Button(action: togglePlayback) {
                    Label(state.isPlaying ? "Stop" : "Play",
                          systemImage: state.isPlaying ? "stop.fill" : "play.fill")
                }
                .controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Station")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Text(state.stationName.isEmpty ? "—" : state.stationName)
                    .font(.headline)
                if !state.stationSlogan.isEmpty {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(state.stationSlogan)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !state.stationMessage.isEmpty {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(state.stationMessage)
                        .foregroundStyle(.secondary)
                }
            }

            MetadataRow(label: "Title", value: state.title)
            MetadataRow(label: "Artist", value: state.artist)

            if !state.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MetadataRow(label: "Album", value: state.album)
            }
            if !state.genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MetadataRow(label: "Genre", value: state.genre)
            }

            if !state.latestImageData.isEmpty {
                ByteImageView(imageBytes: state.latestImageData)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBar: some View {
        HStack {
            Text(state.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "MER %.1f / %.1f dB  ·  BER %.6f",
                        state.merLower, state.merUpper, state.ber))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Actions

    /// Play/stop is inherently asynchronous: commands flow down into the
    /// tuner actor, and results (started/stopped/failed) flow back up as
    /// events that update `state`.
    private func togglePlayback() {
        Task { await togglePlaybackAsync() }
    }

    private func togglePlaybackAsync() async {
        if state.isPlaying {
            guard let current = session else { return }
            session = nil
            await current.stop()
        } else {
            await startPlayback()
        }
    }

    private func startPlayback() async {
        let configuration = TunerConfiguration(
            source: state.source == .rtlSDR ? .rtlSDR(deviceIndex: 0) : .sampleFile,
            frequencyHz: state.frequencyHz,
            program: state.program)

        do {
            let newSession = try TunerSession(sink: state)
            session = newSession
            // Optimistic, so the button feels immediate; the .failed event
            // corrects this if the tuner cannot start.
            state.isPlaying = true
            await newSession.start(configuration)
        } catch {
            session = nil
            state.status = "Error: \(error.localizedDescription)"
        }
    }

    /// Retunes a running RTL-SDR session when the frequency field changes.
    /// Debounced because each keystroke would otherwise reopen the demodulator.
    private func scheduleRetune() {
        retuneTask?.cancel()
        retuneTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            guard state.source == .rtlSDR, state.isPlaying,
                  let session, let frequencyHz = state.frequencyHz else { return }
            await session.retune(frequencyHz: frequencyHz)
        }
    }

    // MARK: - Smoke test

    /// Plays the bundled sample file and self-terminates, printing
    /// `SMOKE_OK` if metadata was received.
    private func runSmokeTest() async {
        state.source = .sampleFile
        await startPlayback()
        try? await Task.sleep(for: .seconds(8))
        if !state.stationName.isEmpty || !state.title.isEmpty {
            fputs("SMOKE_OK: station='\(state.stationName)' title='\(state.title)'\n", stderr)
        } else {
            fputs("SMOKE_FAIL: no metadata received\n", stderr)
        }
        NSApp.terminate(nil)
    }
}

/// A caption label + value row used by the metadata panel.
private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
        }
    }
}

#Preview {
    ContentView()
}
