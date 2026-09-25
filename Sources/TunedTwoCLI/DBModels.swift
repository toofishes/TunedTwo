//
//  DBModels.swift
//  TunedTwo
//

import Foundation
import GRDB

struct Station: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "station"

    var id: UUID
    var frequencyHz: Int
    var createdAt: Date
    var updatedAt: Date

    var country: String
    var fccID: String

    var name: String?
    var slogan: String?
    var message: String?

    var ttn: Bool
    var here: Bool
}

struct Program: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "program"

    var stationID: UUID
    var programID: Int
    var name: String?
    var lotID: Int?

    var id: String { String(format: "%s:%d", stationID.uuidString, programID) }
}

/// Represents the actual file data received. This is split from the file because it is not uncommon to receive
/// duplicate data with different file identifiers and names over time.
struct Nrsc5FileData: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "nrsc5_file_data"

    var hash: Int64
    var data: Data

    var id: Int64 { hash }
}

struct Nrsc5File: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "nrsc5_file"

    var id: UUID
    var stationID: UUID
    var filename: String

    var lotID: Int?
    var lotMime: Int?
    var lotComponentMime: Int?

    var hereType: Int?
    var hereSequence: Int?
    var hereN1: Int?
    var hereN2: Int?
    var hereLatitude1: Double?
    var hereLongitude1: Double?
    var hereLatitude2: Double?
    var hereLongitude2: Double?

    var createdAt: Date
    var timestamp: Date?
    var seenAt: Date?
    var expiresAt: Date?

    var dataHash: Int64

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let stationID = Column(CodingKeys.stationID)
        static let filename = Column(CodingKeys.filename)

        static let lotID = Column(CodingKeys.lotID)
        static let lotMime = Column(CodingKeys.lotMime)
        static let lotComponentMime = Column(CodingKeys.lotComponentMime)

        // ... TODO: fill out the rest here

        static let createdAt = Column(CodingKeys.createdAt)

        // ... TODO: fill out the rest here

        static let dataHash = Column(CodingKeys.dataHash)
    }

    enum CodingKeys: String, CodingKey {
        // TODO: incomplete, fill out the rest as needed
        case id
        case stationID = "station_id"
        case filename
        case lotID = "lot_id"
        case lotMime = "lot_mime"
        case lotComponentMime = "lot_component_mime"
        case createdAt = "created_at"
        case dataHash = "data_hash"
    }
}

extension Nrsc5File {
    static let data = belongsTo(Nrsc5FileData.self, key: "data_hash")
    var data: QueryInterfaceRequest<Nrsc5FileData> {
        request(for: Nrsc5File.data)
    }
}

func fnv1a64(data: Data) -> UInt64 {
    let prime: UInt64 = 1_099_511_628_211
    var hash: UInt64 = 14_695_981_039_346_656_037

    for byte in data {
        hash ^= UInt64(byte)
        hash = hash &* prime
    }
    // TODO: use Int64(bitPattern: hash) to coerce to a value we can store in sqlite3
    return hash
}
