//
//  ByteImageView.swift
//  TunedTwo
//

import SwiftUI
import TunedTwoCore

struct ByteImageView: View {
    let imageData: Data

    var body: some View {
        if let swiftUIImage = createSwiftUIImage(imageData) {
            swiftUIImage
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 100, maxHeight: 100)
        } else {
            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 100, maxHeight: 100)
        }
    }

    // Helper function to handle the conversion
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
