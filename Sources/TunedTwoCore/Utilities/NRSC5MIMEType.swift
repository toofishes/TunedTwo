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
/// (e.g. `"TTN STM Traffic (0xFF8422D7)"`). Unknown values fall back to
/// their hex representation.
public func nameForNRSC5MIMEType(_ mime: UInt32) -> String {
    let hex = String(format: "0x%08X", mime)

    if mime == NRSC5_MIME_PRIMARY_IMAGE {
        return "Primary Image (\(hex))"
    } else if mime == NRSC5_MIME_STATION_LOGO {
        return "Station Logo (\(hex))"
    } else if mime == NRSC5_MIME_NAVTEQ {
        return "NAVTEQ (\(hex))"
    } else if mime == NRSC5_MIME_HERE_TPEG {
        return "HERE TPEG (\(hex))"
    } else if mime == NRSC5_MIME_HERE_IMAGE {
        return "HERE Image (\(hex))"
    } else if mime == NRSC5_MIME_HD_TMC {
        return "HD TMC (\(hex))"
    } else if mime == NRSC5_MIME_HDC {
        return "HDC Audio (\(hex))"
    } else if mime == NRSC5_MIME_TEXT {
        return "Text (\(hex))"
    } else if mime == NRSC5_MIME_JPEG {
        return "JPEG (\(hex))"
    } else if mime == NRSC5_MIME_PNG {
        return "PNG (\(hex))"
    } else if mime == NRSC5_MIME_TTN_TPEG_1 {
        return "TTN TPEG 1 (\(hex))"
    } else if mime == NRSC5_MIME_TTN_TPEG_2 {
        return "TTN TPEG 2 (\(hex))"
    } else if mime == NRSC5_MIME_TTN_TPEG_3 {
        return "TTN TPEG 3 (\(hex))"
    } else if mime == NRSC5_MIME_TTN_STM_TRAFFIC {
        return "TTN STM Traffic (\(hex))"
    } else if mime == NRSC5_MIME_TTN_STM_WEATHER {
        return "TTN STM Weather (\(hex))"
    } else if mime == NRSC5_MIME_UNKNOWN_00000000 {
        return "Unknown (\(hex))"
    } else if mime == NRSC5_MIME_UNKNOWN_1C7D0E29 {
        return "Unknown (\(hex))"
    } else if mime == NRSC5_MIME_UNKNOWN_B81FFAA8 {
        return "Unknown (\(hex))"
    } else if mime == NRSC5_MIME_UNKNOWN_FFFFFFFF {
        return "Unknown (\(hex))"
    }

    return "Unknown (\(hex))"
}
