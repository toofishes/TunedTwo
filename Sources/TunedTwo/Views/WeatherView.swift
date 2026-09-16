//
//  WeatherView.swift
//  TunedTwo
//

import SwiftUI
import MapKit
import TunedTwoCore

class ImageOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let image: CGImage

    init(image: CGImage, rect: MKMapRect) {
        self.image = image
        self.boundingMapRect = rect
        self.coordinate = MKCoordinateRegion(rect).center
        super.init()
    }
}

class ImageOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let imageOverlay = overlay as? ImageOverlay else { return }

        // Convert the geographic bounding box to drawing coordinates
        let rect = self.rect(for: imageOverlay.boundingMapRect)

        context.saveGState()

        // Flip the context geometry because Core Graphics and macOS have inverted Y-axes
        context.translateBy(x: 0, y: rect.origin.y + rect.size.height)
        context.scaleBy(x: 1.0, y: -1.0)

        let flippedRect = CGRect(x: rect.origin.x, y: 0, width: rect.size.width, height: rect.size.height)
        context.draw(imageOverlay.image, in: flippedRect)

        context.restoreGState()
    }
}

/// A SwiftUI bridge to MKMapView so we can use a custom MKOverlayRenderer.
///
/// The declarative `Map` SwiftUI view does not expose a way to vend a custom
/// `MKOverlayRenderer`, so for an image overlay we fall back to wrapping
/// `MKMapView` directly.
struct WeatherMapView: NSViewRepresentable {
    @Binding var visibleRect: MKMapRect
    let image: CGImage?
    let boundingBox: MKMapRect

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView

        configure(mapView, coordinator: context.coordinator)
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        // Refresh the overlay whenever the image changes.
        configure(mapView, coordinator: context.coordinator)

        // Apply camera changes that came from SwiftUI (e.g. a reset button).
        // Guard against programmatic updates so we don't fight the user's
        // gestures or recurse through regionDidChangeAnimated.
        if !context.coordinator.isApplyingBinding,
           !MKMapRectEqualToRect(mapView.visibleMapRect, visibleRect) {
            context.coordinator.isApplyingBinding = true
            mapView.setVisibleMapRect(visibleRect, animated: false)
            context.coordinator.isApplyingBinding = false
        }
    }

    private func configure(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.removeOverlays(mapView.overlays)

        if let image = image {
            let overlay = ImageOverlay(image: image, rect: boundingBox)
            mapView.addOverlay(overlay)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: WeatherMapView
        weak var mapView: MKMapView?
        var isApplyingBinding = false

        init(_ parent: WeatherMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let imageOverlay = overlay as? ImageOverlay {
                return ImageOverlayRenderer(overlay: imageOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isApplyingBinding else { return }

            let newRect = mapView.visibleMapRect
            if !MKMapRectEqualToRect(parent.visibleRect, newRect) {
                parent.visibleRect = newRect
            }
        }
    }
}

struct WeatherView: View {
    let map: WeatherMap

    private static let locationOne = CLLocationCoordinate2D(latitude: 43.69360, longitude: -90.68990)
    private static let locationTwo = CLLocationCoordinate2D(latitude: 39.67031, longitude: -85.30001)

    @State private var visibleRect: MKMapRect = radarBoundingBox

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("Weather")
            WeatherMapView(
                visibleRect: $visibleRect,
                image: map.image,
                boundingBox: Self.radarBoundingBox
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 16) {
                Button("Reset Radar View") {
                    visibleRect = Self.radarBoundingBox
                }
                Text(updated)
            }
        }
    }

    var updated: String {
        guard let ts = map.info?.timestamp else { return "No Weather Radar Data" }
        let formattedTs = ts.formatted(date: .numeric, time: .shortened)
        return "Weather Last Updated: \(formattedTs)"
    }

    private static var radarBoundingBox: MKMapRect {
        let p1 = MKMapPoint(locationOne)
        let p2 = MKMapPoint(locationTwo)
        return MKMapRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p1.x - p2.x),
            height: abs(p1.y - p2.y)
        )
    }
}
