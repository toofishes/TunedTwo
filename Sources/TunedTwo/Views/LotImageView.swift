//
//  LotImageView.swift
//  TunedTwo
//

import SwiftUI
import TunedTwoCore

#if os(macOS)
    import AppKit
    private typealias PlatformImage = NSImage
#else
    import UIKit
    private typealias PlatformImage = UIImage
#endif

/// Caches decoded platform images keyed by LOT file identity.
///
/// Without this, `LotImageView` decodes the same JPEG/PNG bytes on every
/// SwiftUI body evaluation, which becomes expensive as metadata updates
/// stream in. The cache is bounded by `NSCache` and by the `lotCache` size
/// cap in `TunerState`.
@MainActor
private final class LotImageCache {
    static let shared = LotImageCache()

    private var cache = {
        let c = NSCache<NSString, PlatformImage>()
        c.countLimit = 50
        return c
    }()

    private init() {}

    func image(for lot: TunerLotFile) -> PlatformImage? {
        let key = cacheKey(for: lot)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard !lot.data.isEmpty, let image = PlatformImage(data: lot.data) else {
            return nil
        }
        cache.setObject(image, forKey: key, cost: lot.data.count)
        return image
    }

    private func cacheKey(for lot: TunerLotFile) -> NSString {
        // Include size and expiry so a reused lot ID with new contents does
        // not return a stale cached image.
        let expiry = lot.expiry?.timeIntervalSince1970 ?? 0
        return "\(lot.lotID)-\(lot.data.count)-\(expiry)" as NSString
    }
}

struct LotImageView: View {
    let lot: TunerLotFile?
    let defaultSystemImage: String

    var body: some View {
        VStack(alignment: .center) {
            imageToDisplay
                .resizable()
                .scaledToFit()
                .aspectRatio(1.0, contentMode: .fit)
                .frame(idealWidth: 100, maxWidth: 100, idealHeight: 100, maxHeight: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(lot?.lotID.formatted(.number.grouping(.never)) ?? "")
            Text(lot?.expiry?.formatted(date: .numeric, time: .shortened) ?? "")
        }
    }

    /// Resolves the lot data to a SwiftUI `Image`, falling back to the default system image.
    private var imageToDisplay: Image {
        if let lot, let platformImage = LotImageCache.shared.image(for: lot) {
            #if os(macOS)
                return Image(nsImage: platformImage)
            #else
                return Image(uiImage: platformImage)
            #endif
        }
        return Image(systemName: defaultSystemImage)
    }
}

#Preview("Non-Square default") {
    HStack {
        LotImageView(lot: nil, defaultSystemImage: "antenna.radiowaves.left.and.right")
        LotImageView(lot: nil, defaultSystemImage: "music.note")
    }
    .padding(50)
}
