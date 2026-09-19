//
//  LotImageView.swift
//  TunedTwo
//

import SwiftUI
import TunedTwoCore

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
        if let lot, let image = createSwiftUIImage(lot.data) {
            return image
        }
        return Image(systemName: defaultSystemImage)
    }

    /// Helper function to handle the conversion.
    private func createSwiftUIImage(_ data: Data) -> Image? {
        guard !data.isEmpty else { return nil }

        #if os(macOS)
            // macOS implementation using NSImage
            guard let nsImage = NSImage(data: data) else { return nil }
            return Image(nsImage: nsImage)
        #else
            // iOS/watchOS/tvOS implementation using UIImage
            guard let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
        #endif
    }
}

#Preview("Non-Square default") {
    HStack {
        LotImageView(lot: nil, defaultSystemImage: "antenna.radiowaves.left.and.right")
        LotImageView(lot: nil, defaultSystemImage: "music.note")
    }
    .padding(50)
}
