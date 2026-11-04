//
//  TrafficView.swift
//  TunedTwo
//

import SwiftUI
import TunedTwoCore

struct TrafficView: View {
    let map: TrafficMap

    var body: some View {
        VStack(alignment: .center, spacing: Theme.itemSpacing) {
            if let composite = map.composite {
                Image(composite, scale: 1.0, orientation: .up, label: Text("Traffic"))
                    .resizable().scaledToFit()
            } else {
                ContentUnavailableView(
                    "No Traffic Data",
                    systemImage: "map",
                    description: Text("Traffic maps will appear here when received from the station."))
            }
            Text(updated)
        }
    }

    var updated: String {
        guard let ts = map.maximumTimestamp() else { return "No Traffic Data" }
        let formattedTs = ts.formatted(date: .numeric, time: .shortened)
        return "Traffic Last Updated: \(formattedTs)"
    }
}
