//
//  NRSC5MIMEType.swift
//  TunedTwo
//
//  Human-readable names for NRSC5 MIME type constants.
//

import Foundation
import nrsc5

/// Returns a display name for an NRSC5 MIME type value.
///
/// Known values are translated to readable names plus their hex value
/// (e.g. `"TTN STM Traffic"`). Unknown values fall back to
/// their hex representation.
public func nameForNRSC5MIMEType(_ mime: UInt32) -> String {
    if let name = nrsc5MimeNames[mime] {
        return name
    }
    let hex = String(format: "0x%08X", mime)
    return "Unknown (\(hex))"
}

private let nrsc5MimeNames: [UInt32: String] = [
    NRSC5_MIME_PRIMARY_IMAGE: "Primary Image",
    NRSC5_MIME_STATION_LOGO: "Station Logo",
    UInt32(NRSC5_MIME_NAVTEQ): "NAVTEQ",
    NRSC5_MIME_HERE_TPEG: "HERE TPEG",
    NRSC5_MIME_HERE_IMAGE: "HERE Image",
    NRSC5_MIME_HD_TMC: "HD TMC",
    UInt32(NRSC5_MIME_HDC): "HDC Audio",
    NRSC5_MIME_TEXT: "Text",
    UInt32(NRSC5_MIME_JPEG): "JPEG",
    UInt32(NRSC5_MIME_PNG): "PNG",
    NRSC5_MIME_TTN_TPEG_1: "TTN TPEG 1",
    UInt32(NRSC5_MIME_TTN_TPEG_2): "TTN TPEG 2",
    UInt32(NRSC5_MIME_TTN_TPEG_3): "TTN TPEG 3",
    NRSC5_MIME_TTN_STM_TRAFFIC: "TTN STM Traffic",
    NRSC5_MIME_TTN_STM_WEATHER: "TTN STM Weather",
    UInt32(NRSC5_MIME_UNKNOWN_00000000): "Unknown",
    UInt32(NRSC5_MIME_UNKNOWN_1C7D0E29): "Unknown",
    NRSC5_MIME_UNKNOWN_B81FFAA8: "Unknown",
    NRSC5_MIME_UNKNOWN_FFFFFFFF: "Unknown",
]
