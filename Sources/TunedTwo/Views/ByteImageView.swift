//
//  ByteImageView.swift
//  TunedTwo
//

import SwiftUI
import TunedTwoCore

struct ByteImageView: View {
    // Example: A raw array of [UInt8] bytes representing an image (PNG, JPEG, etc.)
    let imageBytes: [UInt8]

    var body: some View {
        if let swiftUIImage = createSwiftUIImage(from: imageBytes) {
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
    private func createSwiftUIImage(from bytes: [UInt8]) -> Image? {
        guard !bytes.isEmpty else { return nil }

        let data = Data(bytes)

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
