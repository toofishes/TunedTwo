//
//  MapProcessor.swift
//  TunedTwo
//
//  Offloads traffic and weather map image decoding from the main actor.
//

import CoreGraphics
import Foundation

/// Processes traffic/weather map image files off the main actor.
///
/// `TrafficMap` and `WeatherMap` are value types that contain immutable
/// `CGImage` references. `CGImage` is `Sendable` on the supported deployment
/// targets, so the maps can be copied into and out of this actor safely.
actor MapProcessor {
    func processTrafficImageFile(
        name: String, data: Data, currentMap: TrafficMap
    ) -> (TrafficMap, TrafficMapIngestOutcome) {
        var map = currentMap
        let outcome = map.processImageFile(name: name, data: data)
        return (map, outcome)
    }

    func processTrafficHereImage(
        _ hereImage: TunerHereImage, currentMap: TrafficMap
    ) -> (TrafficMap, TrafficMapIngestOutcome) {
        var map = currentMap
        let outcome = map.processHereImageFile(hereImage: hereImage)
        return (map, outcome)
    }

    func processWeatherImageFile(
        name: String, data: Data, currentMap: WeatherMap
    ) -> (WeatherMap, WeatherMapIngestOutcome) {
        var map = currentMap
        let outcome = map.processImageFile(name: name, data: data)
        return (map, outcome)
    }

    func processWeatherHereImage(
        _ hereImage: TunerHereImage, currentMap: WeatherMap
    ) -> (WeatherMap, WeatherMapIngestOutcome) {
        var map = currentMap
        let outcome = map.processHereImageFile(hereImage: hereImage)
        return (map, outcome)
    }
}
