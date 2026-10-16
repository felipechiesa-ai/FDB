import CoreGraphics
import SwiftUI

/// A square image preview. Shows a placeholder while loading, and whenever no image is set.
struct MediaThumbnailView: View {
    @Environment(LibraryModel.self) private var library

    let fileName: String?
    let placeholder: String
    var size: CGFloat = 120

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: placeholder)
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(fileName == nil ? "No image" : "Image")
        .task(id: fileName) {
            guard let fileName else {
                image = nil
                return
            }
            image = await library.thumbnail(fileName: fileName, maxPixelSize: Int(size * 2))
        }
    }
}
