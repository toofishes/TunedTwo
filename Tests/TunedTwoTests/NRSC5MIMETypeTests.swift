//
//  NRSC5MIMETypeTests.swift
//  TunedTwoTests
//
//  Smoke tests for MIME type name helpers.
//

import Testing

@testable import TunedTwoCore

@Suite("DSD MIME type names")
struct NRSC5MIMETypeTests {
    @Test("returns a known DSD MIME type name")
    func knownDSDMIMEType() {
        #expect(nameForDSDMIMEType(0xC3E) == "NAVTEQ")
    }

    @Test("returns Unknown with hex formatting for an unrecognized DSD MIME type")
    func unknownDSDMIMEType() {
        #expect(nameForDSDMIMEType(0x123) == "Unknown (0x123)")
    }
}
