//
//  LogEvent.swift
//  TunedTwo
//

import Foundation
import SwiftUI

struct LogEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let title: String
    let description: String
    let systemImage: String
    let tintColor: Color
}
