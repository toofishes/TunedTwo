//
//  ContentView.swift
//  TunedTwo
//
//  Main SwiftUI view.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var state = TunerState()
    @State private var session: TunerSession?
    @State private var smokeTestTimer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            header
            controls
            Divider()
            metadata
            Spacer()
            statusBar
        }
        .padding()
        .frame(minWidth: 520, minHeight: 380)
        .onChange(of: state.program) { _, newProgram in
            session?.programChanged(to: newProgram)
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["TUNEDTWO_SMOKE_TEST"] == "1" {
                state.source = .sampleFile
                togglePlayback()
                smokeTestTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { _ in
                    if !self.state.stationName.isEmpty || !self.state.title.isEmpty {
                        fputs("SMOKE_OK: station='\(self.state.stationName)' title='\(self.state.title)'\n", stderr)
                    } else {
                        fputs("SMOKE_FAIL: no metadata received\n", stderr)
                    }
                    NSApp.terminate(nil)
                }
            }
        }
        .onDisappear {
            smokeTestTimer?.invalidate()
            session?.stop()
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "radio")
                .font(.largeTitle)
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
            }

            MetadataRow(label: "Title", value: state.title)
            MetadataRow(label: "Artist", value: state.artist)

            if !state.album.isEmpty {
                MetadataRow(label: "Album", value: state.album)
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
            Text(String(format: "MER %.1f / %.1f dB  ·  BER %.4f",
                        state.merLower, state.merUpper, state.ber))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Actions

    private func togglePlayback() {
        if state.isPlaying {
            session?.stop()
        } else {
            do {
                let newSession = try TunerSession(state: state)
                session = newSession
                newSession.start()
            } catch {
                state.status = "Error: \(error.localizedDescription)"
            }
        }
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
