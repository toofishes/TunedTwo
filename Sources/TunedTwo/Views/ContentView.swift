//
//  ContentView.swift
//  TunedTwo
//
//  Main SwiftUI view.
//

import SwiftUI
import TunedTwoCore

struct ContentView: View {
    @State private var state: TunerState
    private var session: TunerSession
    @State private var retuneTask: Task<Void, Never>?
    @State private var selectedTab: String = ""

    init() {
        let newState = TunerState()
        if let samplePath = ProcessInfo.processInfo.environment["TUNEDTWO_SAMPLE_FILE"] {
            newState.isSampleFile = true
            newState.sampleFilePath = samplePath
        }
        state = newState
        session = .init(sink: newState)
    }

    var body: some View {
        VStack(spacing: Theme.sectionSpacing) {
            ContentHeader()
            Controls(state: $state) {
                togglePlayback()
            }
            Divider()
            TabView(selection: $selectedTab) {
                Tab("Radio", systemImage: "radio", value: "radio") {
                    RadioView(state: state)
                }

                Tab("Traffic", systemImage: "map", value: "traffic") {
                    TrafficView(map: state.traffic)
                }

                Tab("Weather", systemImage: "sun.rain", value: "weather") {
                    WeatherView(map: state.weather)
                }

                Tab("Logs", systemImage: "list.bullet.rectangle", value: "logs") {
                    EventLogView(state: state, visible: selectedTab == "logs")
                }
            }
            Divider()
            StatusBar(state: state)
        }
        .padding(Theme.defaultPadding)
        .frame(minWidth: Theme.windowMinWidth, minHeight: Theme.windowMinHeight)
        .onChange(of: state.currentProgram) { _, newProgram in
            Task { await session.setProgram(newProgram) }
        }
        .onChange(of: state.frequencyMHz) { _, _ in
            scheduleRetune()
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

    // MARK: - Actions

    private func togglePlayback() {
        Task { await togglePlaybackAsync() }
    }

    private func togglePlaybackAsync() async {
        if state.isPlaying {
            await session.stop()
        } else {
            await startPlayback()
        }
    }

    private func startPlayback() async {
        let configuration: TunerConfiguration
        if let samplePath = ProcessInfo.processInfo.environment["TUNEDTWO_SAMPLE_FILE"] {
            configuration = TunerConfiguration(
                source: .samplePipe(path: samplePath),
                frequencyHz: nil,
                program: state.currentProgram)
            state.isSampleFile = true
            state.sampleFilePath = samplePath
        } else {
            configuration = TunerConfiguration(
                source: .rtlSDR(deviceIndex: 0),
                frequencyHz: state.frequencyHz,
                program: state.currentProgram)
            state.isSampleFile = false
            state.sampleFilePath = nil
        }

        // Optimistic, so the button feels immediate; the .failed event
        // corrects this if the tuner cannot start.
        state.isPlaying = true
        state.clearForFrequencyChange()
        await session.start(configuration)
    }

    /// Retunes a running RTL-SDR session when the frequency field changes.
    /// Debounced because each keystroke would otherwise reopen the demodulator.
    private func scheduleRetune() {
        retuneTask?.cancel()
        retuneTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            guard !state.isSampleFile, state.isPlaying,
                let frequencyHz = state.frequencyHz
            else { return }
            await session.retune(frequencyHz: frequencyHz)
            state.clearForFrequencyChange()
        }
    }

    // MARK: - Smoke test

    /// Starts playback and waits for metadata, then self-terminates and
    /// prints `SMOKE_OK` or `SMOKE_FAIL`.
    private func runSmokeTest() async {
        await startPlayback()
        try? await Task.sleep(for: .seconds(8))
        let ps = state.currentProgramState
        if !state.stationName.isEmpty || !ps.title.isEmpty {
            fputs("SMOKE_OK: station='\(state.stationName)' title='\(ps.title)'\n", stderr)
        } else {
            fputs(
                "SMOKE_FAIL: no metadata received (status='\(state.status)', events=\(state.eventCounts))\n",
                stderr
            )
        }
        NSApp.terminate(nil)
    }
}

// MARK: - Subviews

private struct ContentHeader: View {
    var body: some View {
        HStack {
            Image(systemName: "radio")
                .font(Theme.Fonts.appIcon)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
                Text("TunedTwo")
                    .font(Theme.Fonts.appTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Native macOS HD Radio")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
    }
}

extension BinaryFloatingPoint {
    func roundedToFMFrequency() -> Self {
        // US FM frequencies range from 87.9 to 107.9
        // Align the grid to multiples of 0.2 by subtracting 0.1
        let shifted = (self - 0.1) * 5.0
        let rounded = shifted.rounded(.toNearestOrEven)
        return (rounded * 0.2) + 0.1
    }
}

private struct Controls: View {
    @Binding var state: TunerState
    let togglePlayback: () -> Void

    var body: some View {
        Form {
            Section {
                if state.isSampleFile {
                    LabeledContent("Sample File") {
                        Text(state.sampleFilePath ?? "")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    HStack {
                        let frequencyRange = 87.9...107.9
                        let frequencyBinding = Binding<Double>(
                            get: { state.frequencyMHz },
                            set: { newValue in
                                if newValue < frequencyRange.lowerBound {
                                    state.frequencyMHz = frequencyRange.lowerBound
                                } else if newValue > frequencyRange.upperBound {
                                    state.frequencyMHz = frequencyRange.upperBound
                                } else {
                                    state.frequencyMHz = newValue.roundedToFMFrequency()
                                }
                            }
                        )
                        TextField(
                            "Frequency", value: frequencyBinding,
                            format: .number.grouping(.never).precision(.fractionLength(1))
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Theme.frequencyFieldWidth)

                        Text("MHz")
                            .font(Theme.Fonts.meta)
                            .foregroundStyle(.secondary)

                        Stepper("", value: $state.frequencyMHz, in: frequencyRange, step: 0.2)
                            .labelsHidden()
                    }
                }

                Picker("Program", selection: $state.currentProgram) {
                    ForEach(state.programStates.indices, id: \.self) { i in
                        Text("HD\(i + 1)").tag(i).selectionDisabled(state.programStates[i].available == false)
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
}

private struct StatusBar: View {
    let state: TunerState

    var body: some View {
        HStack {
            let programState = state.currentProgramState
            Text(state.status)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            Spacer()
            Text("\(Double(programState.bitsPerSecond) / 1000.0, format: .number.precision(.fractionLength(1))) kbps")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
            Text(
                "MER \(state.merLower, format: .number.precision(.fractionLength(1))) / \(state.merUpper, format: .number.precision(.fractionLength(1))) dB · BER \(state.ber, format: .number.precision(.fractionLength(6)))"
            )
            .font(Theme.Fonts.meta)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
            .help("\(programState.crcErrors) CRC Errors")
        }
    }
}

#Preview {
    ContentView()
}
