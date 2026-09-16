//
//  LogEvent.swift
//  TunedTwo
//
//  A single entry in the station activity log shown in the UI.
//

import Foundation
import SwiftUI

public struct LogEvent: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let title: String
    public let description: String
    public let systemImage: String
    public let tintColor: Color

    public init(timestamp: Date,
                title: String,
                description: String,
                systemImage: String,
                tintColor: Color) {
        self.timestamp = timestamp
        self.title = title
        self.description = description
        self.systemImage = systemImage
        self.tintColor = tintColor
    }
}
