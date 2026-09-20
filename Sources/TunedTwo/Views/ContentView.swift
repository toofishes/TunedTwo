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
                    RadioView(state: state, programState: state.programStates[state.currentProgram])
                }

                Tab("Traffic", systemImage: "map") {
                    TrafficView(map: state.traffic)
                }

                Tab("Weather", systemImage: "sun.rain") {
                    WeatherView(map: state.weather)
                }

                Tab("Logs", systemImage: "list.bullet.rectangle") {
                    EventLogView(state: state)
                        .onAppear { state.isLogsVisible = true }
                        .onDisappear { state.isLogsVisible = false }
                }
            }
            Divider()
            StatusBar(
                state: state,
                bitsPerSecond: state.programStates[state.currentProgram].bitsPerSecond,
                crcErrors: state.programStates[state.currentProgram].crcErrors)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 440)
        .onChange(of: state.currentProgram) { _, newProgram in
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

                Picker("Program", selection: $state.currentProgram) {
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
            program: state.currentProgram)

        do {
            let newSession = try TunerSession(sink: state)
            session = newSession
            // Optimistic, so the button feels immediate; the .failed event
            // corrects this if the tuner cannot start.
            state.isPlaying = true
            state.clearForFrequencyChange()
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
            state.clearForFrequencyChange()
        }
    }

    // MARK: - Smoke test

    /// Plays the bundled sample file and self-terminates, printing
    /// `SMOKE_OK` if metadata was received.
    private func runSmokeTest() async {
        state.source = .sampleFile
        await startPlayback()
        try? await Task.sleep(for: .seconds(8))
        let ps = state.programStates[state.currentProgram]
        if !state.stationName.isEmpty || !ps.title.isEmpty {
            fputs("SMOKE_OK: station='\(state.stationName)' title='\(ps.title)'\n", stderr)
        } else {
            fputs("SMOKE_FAIL: no metadata received\n", stderr)
        }
        NSApp.terminate(nil)
    }
}

private struct StatusBar: View {
    let state: TunerState
    let bitsPerSecond: Int
    let crcErrors: Int

    var body: some View {
        HStack {
            Text(state.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f kbps", Double(bitsPerSecond) / 1000.0))
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
            .help("\(crcErrors) CRC Errors")
        }
    }
}

#Preview {
    ContentView()
}
