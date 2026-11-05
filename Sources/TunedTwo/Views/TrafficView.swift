//
//  TrafficView.swift
//  TunedTwo
//

import SwiftUI
import TunedTwoCore

struct TrafficView: View {
    let map: TrafficMap

    var body: some View {
        if let composite = map.composite {
            VStack(alignment: .center, spacing: Theme.itemSpacing) {
                Image(composite, scale: 1.0, orientation: .up, label: Text("Traffic"))
                    .resizable().scaledToFit()
                Text(updated)
                    .font(Theme.Fonts.bodySecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            ContentUnavailableView(
                "No Traffic Data",
                systemImage: "map",
                description: Text("Traffic maps will appear here when received from the station."))
        }
    }

    var updated: String {
        guard let ts = map.maximumTimestamp() else { return "No Traffic Data" }
        let formattedTs = ts.formatted(date: .numeric, time: .shortened)
        return "Last Updated: \(formattedTs)"
    }
}
