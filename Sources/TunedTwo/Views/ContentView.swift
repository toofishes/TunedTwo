//
//  ContentView.swift
//  TunedTwo
//
//  Main SwiftUI view.
//

import SwiftUI
import TunedTwoCore

struct ContentView: View {
    @State private var state = TunerState()
    @State private var session: TunerSession?
    @State private var retuneTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            header
            controls
            Divider()
            TabView {
                Tab("Radio", systemImage: "radio") {
                    metadata
                }

                Tab("Traffic", systemImage: "map") {
                    TrafficView(map: state.traffic)
                }

                Tab("Weather", systemImage: "sun.rain") {
                    WeatherView(map: state.weather)
                }

                Tab("Logs", systemImage: "list.bullet.rectangle") {
                    EventLogView(
                        events: state.logEntries,
                        eventCounts: state.eventCounts
                    )
                    .onAppear { state.isLogsVisible = true }
                    .onDisappear { state.isLogsVisible = false }
                }
            }
            Divider()
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

                HStack {
                    TextField("Frequency", text: $state.frequencyMHz)
                        .textFieldStyle(.roundedBorder)
                        .disabled(state.source == .sampleFile)
                        .frame(width: 120)
                    Text("MHz")
                        .foregroundStyle(.secondary)
                }
                //.fixedSize(horizontal: true, vertical: false)

                Picker("Program", selection: $state.program) {
                    ForEach(0..<8) { i in
                        Text("HD\(i + 1)").tag(i)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button(action: togglePlayback) {
                    Label(
                        state.isPlaying ? "Stop" : "Play",
                        systemImage: state.isPlaying ? "stop.fill" : "play.fill")
                }
                .controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            stationMetadata
            Divider()
            nowPlaying
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stationMetadata: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                MetadataRow(label: "Station", value: state.stationName)
                MetadataRow(label: "Slogan", value: state.stationSlogan)
                MetadataRow(label: "Message", value: state.stationMessage)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ByteImageView(imageData: state.latestStationImage)
        }
    }

    private var nowPlaying: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                MetadataRow(label: "Title", value: state.title)
                MetadataRow(label: "Artist", value: state.artist)
                MetadataRow(label: "Album", value: state.album)
                MetadataRow(label: "Genre", value: state.genre)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ByteImageView(imageData: state.latestCoverArt)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(state.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f kbps", Double(state.bitsPerSecond) / 1000.0))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(
                String(
                    format: "MER %.1f / %.1f dB · BER %.6f",
                    state.merLower, state.merUpper, state.ber)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .help("\(state.crcErrors) CRC Errors")
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
                let session, let frequencyHz = state.frequencyHz
            else { return }
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
