//
//  DBTest.swift
//  TunedTwo
//

import ArgumentParser
import Foundation
import GRDB

func makeDatabaseQueue() throws -> DatabaseQueue {
    // 1. Get the proper directory path (e.g., Application Support)
    let fileManager = FileManager.default
    let appSupportURL = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )

    try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    let databaseURL = appSupportURL.appendingPathComponent("db.sqlite")
    fputs("opening database at \(databaseURL.path)\n", stderr)
    let dbQueue = try DatabaseQueue(path: databaseURL.path)

    return dbQueue
}

struct DBTestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test-db",
        abstract: "Test creating and migrating the database",
    )

    mutating func run() {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("Create authors") { db in
            try db.create(table: "nrsc5_file_data") { t in
                t.primaryKey("hash", .integer)
                t.column("data", .blob).notNull()
            }

            try db.create(table: "nrsc5_file") { t in
                t.primaryKey("id", .text)
                t.column("country_code", .text).notNull()
                t.column("station_id", .integer).notNull()
                t.column("filename", .text).notNull()

                t.column("lot_id", .integer).indexed()
                t.column("lot_mime", .integer)
                t.column("lot_component_mime", .integer)

                t.column("here_type", .integer)
                t.column("here_sequence", .integer)
                t.column("here_n1", .integer)
                t.column("here_n2", .integer)
                t.column("here_latitude_1", .real)
                t.column("here_longitude_1", .real)
                t.column("here_latitude_2", .real)
                t.column("here_longitude_2", .real)

                t.column("created_at", .real).notNull()
                t.column("timestamp", .real)
                t.column("seen_at", .real)
                t.column("expires_at", .real)

                t.column("data_hash", .integer).notNull().indexed()
            }
        }

        do {
            let dbQueue = try makeDatabaseQueue()

            fputs("Applying database migrations...\n", stderr)
            try migrator.migrate(dbQueue)

            try dbQueue.write { db in
                //try NRSC5File(id: UU  ID()).insert(db)
                //try NRSC5File(id: UUID()).insert(db)
            }

            try dbQueue.read { db in
                //let file = try NRSC5File.find(db, id: UUID())
                let latestFiles =
                    try Nrsc5File
                    .order(\.createdAt.desc)
                    .limit(10)
                    .fetchAll(db)
            }
        } catch {
            fputs("Error: \(error)\n", stderr)
        }
    }
}
