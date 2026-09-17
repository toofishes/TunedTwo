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
            NowPlaying(programState: programState)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ByteImageView(imageData: state.latestStationImage)
        }
    }
}

private struct NowPlaying: View {
    let programState: ProgramState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                MetadataRow(label: "Title", value: programState.title)
                MetadataRow(label: "Artist", value: programState.artist)
                MetadataRow(label: "Album", value: programState.album)
                MetadataRow(label: "Genre", value: programState.genre)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ByteImageView(imageData: programState.latestCoverArt)
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
