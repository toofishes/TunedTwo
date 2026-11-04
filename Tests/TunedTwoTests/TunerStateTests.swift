//
//  TunerStateTests.swift
//  TunedTwoTests
//
//  Tests for the MainActor application state that drives the SwiftUI UI.
//

import Foundation
import Testing

@testable import TunedTwoCore

/// NRSC5 MIME constants, duplicated here so the tests do not need to import
/// the C library directly. These are fixed NRSC5-spec values.
private let mimeJPEG: UInt32 = 0x1E65_3E9C
private let mimePNG: UInt32 = 0x4F32_8CA0

@MainActor
struct TunerStateTests {
    @Test func defaultState() {
        let state = TunerState()

        #expect(state.source == .rtlSDR)
        #expect(state.frequencyMHz == 103.5)
        #expect(state.frequencyHz == 103_500_000)
        #expect(state.currentProgram == 0)
        #expect(state.isPlaying == false)
        #expect(state.status == "Ready")
        #expect(state.stationName == "")
        #expect(state.stationID == -1)
        #expect(state.merLower == 0)
        #expect(state.merUpper == 0)
        #expect(state.ber == 0)
        #expect(state.logEntries.isEmpty)
        #expect(state.eventCounts.isEmpty)
    }

    @Test func currentProgramStateReflectsSelection() {
        let state = TunerState()

        #expect(state.currentProgramState === state.programStates[0])

        state.currentProgram = 3
        #expect(state.currentProgramState === state.programStates[3])
    }

    @Test func clearForFrequencyChangeResetsStationAndProgramState() async {
        let state = TunerState()
        state.stationName = "KOSF"
        state.stationID = 1234
        state.programStates[0].available = true
        state.programStates[0].title = "Some Song"
        state.merLower = 10
        state.ber = 0.01

        state.clearForFrequencyChange()

        #expect(state.stationName == "")
        #expect(state.stationID == -1)
        #expect(state.stationLocation == nil)
        #expect(state.programStates[0].available == false)
        #expect(state.programStates[0].title == "")
        #expect(state.merLower == 0)
        #expect(state.ber == 0)
        #expect(state.lotCache.isEmpty)
    }

    @Test func startedAndStoppedEventsUpdatePlaybackState() async {
        let state = TunerState()

        await state.tunerSessionDidEmit(.started)
        #expect(state.isPlaying == true)
        #expect(state.status == "Playing")
        #expect(state.eventCounts["started"] == 1)

        await state.tunerSessionDidEmit(.stopped)
        #expect(state.isPlaying == false)
        #expect(state.status == "Stopped")
        #expect(state.eventCounts["stopped"] == 1)
    }

    @Test func failedEventUpdatesStatusAndLogs() async {
        let state = TunerState()

        await state.tunerSessionDidEmit(.failed(message: "device not found"))

        #expect(state.isPlaying == false)
        #expect(state.status == "Error: device not found")
        #expect(state.logEntries.last?.title == "Tuner Failed")
        #expect(state.logEntries.last?.description == "device not found")
        #expect(state.eventCounts["failed"] == 1)
    }

    @Test func merAndBerEventsUpdateMetrics() async {
        let state = TunerState()

        await state.tunerSessionDidEmit(.mer(lower: 12.5, upper: 14.0))
        #expect(state.merLower == 12.5)
        #expect(state.merUpper == 14.0)

        await state.tunerSessionDidEmit(.ber(cber: 0.00123))
        #expect(state.ber == 0.00123)
    }

    @Test func stationMetadataEventsUpdateStateAndLog() async {
        let state = TunerState()

        await state.tunerSessionDidEmit(.stationName("KOSF"))
        #expect(state.stationName == "KOSF")
        #expect(state.eventCounts["stationName"] == 1)

        await state.tunerSessionDidEmit(.stationSlogan("Classic Rock"))
        #expect(state.stationSlogan == "Classic Rock")

        await state.tunerSessionDidEmit(.stationMessage("Hello"))
        #expect(state.stationMessage == "Hello")

        await state.tunerSessionDidEmit(.stationID(countryCode: "US", fccFacilityID: 56789))
        #expect(state.stationCountry == "US")
        #expect(state.stationID == 56789)
    }

    @Test func id3EventUpdatesProgramState() async {
        let state = TunerState()
        let id3 = TunerID3(
            program: 2,
            title: "Test Title",
            artist: "Test Artist",
            album: "Test Album",
            genre: "Rock",
            showCover: true,
            lotID: 42)

        await state.tunerSessionDidEmit(.id3(program: 2, id3: id3))

        let program = state.programStates[2]
        #expect(program.title == "Test Title")
        #expect(program.artist == "Test Artist")
        #expect(program.album == "Test Album")
        #expect(program.genre == "Rock")
        #expect(program.showCover == true)
        #expect(program.coverLotID == 42)
    }

    @Test func imageLotFileIsCached() async {
        let state = TunerState()
        let file = TunerLotFile(
            lotID: 7,
            mime: mimePNG,
            name: "cover.png",
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            expiry: nil)

        await state.tunerSessionDidEmit(.lot(file: file, service: nil, component: nil))

        #expect(state.lotCache[7] == file)
        #expect(state.eventCounts["lot"] == 1)
    }

    @Test func nonImageLotFileIsNotCached() async {
        let state = TunerState()
        let file = TunerLotFile(
            lotID: 8,
            mime: 0x1234_5678,
            name: "config.txt",
            data: Data("config".utf8),
            expiry: nil)

        await state.tunerSessionDidEmit(.lot(file: file, service: nil, component: nil))

        #expect(state.lotCache[8] == nil)
        #expect(state.eventCounts["lot"] == 1)
    }

    @Test func referencedImageLotIsProtectedFromEviction() async {
        let state = TunerState()

        // Fill the cache to its private limit with unreferenced images first.
        for id in 1...200 {
            let file = TunerLotFile(
                lotID: id,
                mime: mimeJPEG,
                name: "\(id).jpg",
                data: Data("image\(id)".utf8),
                expiry: nil)
            await state.tunerSessionDidEmit(.lot(file: file, service: nil, component: nil))
        }

        // Now add a referenced image. The cache should evict the oldest
        // unreferenced entries rather than the image currently on screen.
        let referenced = TunerLotFile(
            lotID: 1000,
            mime: mimePNG,
            name: "logo.png",
            data: Data("logo".utf8),
            expiry: nil)
        state.programStates[0].programLotID = 1000
        await state.tunerSessionDidEmit(.lot(file: referenced, service: nil, component: nil))

        #expect(state.lotCache[1000] == referenced)
    }

    @Test func logEntriesAreCapped() async {
        let state = TunerState()

        for i in 0..<10_010 {
            await state.tunerSessionDidEmit(.stationName("Station \(i)"))
        }

        // The private maxLogEntries is 10_000; excess entries should be trimmed.
        #expect(state.logEntries.count == 10_000)
        #expect(state.logEntries.first?.description == "Station 10")
        #expect(state.logEntries.last?.description == "Station 10009")
    }
}
