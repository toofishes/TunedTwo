//
//  TrafficView.swift
//  TunedTwo
//

import SwiftUI
import TunedTwoCore

struct TrafficView: View {
    let map: TrafficMap

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("Traffic")
            if let composite = map.composite {
                Image(composite, scale: 1.0, orientation: .up, label: Text("Traffic"))
                    .resizable().scaledToFit()
            } else {
                Image(systemName: "map").resizable().scaledToFit()
            }
            Text(updated)
        }
    }
    
    var updated: String {
        guard map.maximumTimestamp() != nil else { return "No Traffic Data" }
        let ts = map.maximumTimestamp()!.formatted(date: .numeric, time: .shortened)
        return "Traffic Last Updated: \(ts)"
    }
}
