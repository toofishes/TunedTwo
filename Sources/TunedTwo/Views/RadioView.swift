//
//  RadioView.swift
//  TunedTwo
//

import SwiftUI
import TunedTwoCore

struct RadioView: View {
    let state: TunerState
    let programState: ProgramState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StationInfo(state: state)
            Divider()
            NowPlaying(programState: programState, lotCache: state.lotCache)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StationInfo: View {
    let state: TunerState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                MetadataRow(label: "Station", value: state.stationName)
                MetadataRow(label: "Slogan", value: state.stationSlogan)
                MetadataRow(label: "Message", value: state.stationMessage)
                MetadataRow(label: "Station ID", value: state.stationID.formatted(.number.grouping(.never)))
                MetadataRow(label: "Country Code", value: state.stationCountry)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NowPlaying: View {
    let programState: ProgramState
    var lotCache: [Int: LotFile]

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                MetadataRow(label: "Service", value: programState.serviceName)
                MetadataRow(label: "Title", value: programState.title)
                MetadataRow(label: "Artist", value: programState.artist)
                MetadataRow(label: "Album", value: programState.album)
                MetadataRow(label: "Genre", value: programState.genre)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LotImageView(
                lot: lotCache[programState.programLotID], defaultSystemImage: "antenna.radiowaves.left.and.right")
            LotImageView(lot: lotCache[programState.coverLotID], defaultSystemImage: "music.note")
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
                .frame(width: 80, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
        }
    }
}
