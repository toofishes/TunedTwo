//
//  WeatherView.swift
//  TunedTwo
//

import SwiftUI
import TunedTwoCore

struct WeatherView: View {
    let map: WeatherMap

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("Weather")
            if let image = map.image {
                Image(image, scale: 1.0, orientation: .up, label: Text("Traffic"))
                    .resizable().scaledToFit()
            } else {
                Image(systemName: "sun.rain").resizable().scaledToFit()
            }
            Text(updated)
        }
    }

    var updated: String {
        guard let ts = map.info?.timestamp else { return "No Weather Radar Data" }
        let formattedTs = ts.formatted(date: .numeric, time: .shortened)
        return "Weather Last Updated: \(formattedTs)"
    }
}
