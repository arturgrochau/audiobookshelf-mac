import ABSCore
import AppKit
import SwiftUI

/// covers/BookCover.vue: the cover at the library's aspect ratio. A cover whose
/// own shape differs is letterboxed over a blurred copy of itself; items with
/// no cover get the placeholder with title and author printed on it.
struct BookCover: View {
  let item: LibraryItem?
  let width: CGFloat
  var aspect: Double = 1
  var pixelWidth: Int = 400
  var itemId: String?
  var updatedAt: Double?
  var hasCover: Bool?

  private var height: CGFloat { width * aspect }

  private var url: URL? {
    if let item {
      if let local = DownloadManager.shared.localCoverURL(item.id), !AppModel.shared.isOnline {
        return local
      }
      return AppModel.shared.coverURL(item)
    }
    if let itemId, hasCover != false {
      return AppModel.shared.coverURL(itemId: itemId, updatedAt: updatedAt)
    }
    return nil
  }

  var body: some View {
    ZStack {
      Theme.primary
      if let url {
        CoverImage(url: url, pixelWidth: pixelWidth, aspect: aspect) { placeholder }
      } else {
        placeholder
      }
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: 2))
  }

  private var placeholder: some View {
    ZStack {
      if let img = Self.placeholderImage {
        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
      }
      VStack(spacing: 4) {
        Text(String((item?.title ?? "").prefix(57)))
          .font(Theme.sans(width * 0.1))
          .multilineTextAlignment(.center)
        Text(String((item?.authorLine ?? "").prefix(27)))
          .font(Theme.sans(width * 0.08))
          .opacity(0.75)
      }
      .foregroundStyle(Color(red: 247 / 255, green: 223 / 255, blue: 187 / 255))
      .padding(width * 0.1)
    }
    .frame(width: width, height: height)
    .clipped()
  }

  static let placeholderImage: NSImage? = Bundle.main.resourceURL
    .flatMap { NSImage(contentsOf: $0.appendingPathComponent("images/book_placeholder.jpg")) }
}

private struct CoverImage<Placeholder: View>: View {
  let url: URL
  let pixelWidth: Int
  let aspect: Double
  @ViewBuilder var placeholder: () -> Placeholder
  @State private var image: NSImage?
  @State private var loadedURL: URL?
  @State private var failed = false

  var body: some View {
    // The memory cache wins, so a changed URL (edited cover) never shows the old image.
    let img =
      ImagePipeline.shared.cached(url, pixelWidth: pixelWidth) ?? (loadedURL == url ? image : nil)
    GeometryReader { geo in
      if let img {
        let imgAspect = img.size.height / max(1, img.size.width)
        if abs(imgAspect - aspect) > 0.15 {
          ZStack {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
              .frame(width: geo.size.width, height: geo.size.height)
              .blur(radius: 20)
              .clipped()
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
          }
        } else {
          Image(nsImage: img).resizable()
        }
      } else if failed {
        placeholder()
      } else {
        Theme.primary
      }
    }
    .task(id: url) {
      if ImagePipeline.shared.cached(url, pixelWidth: pixelWidth) != nil { return }
      failed = false
      let loaded = await ImagePipeline.shared.image(url, pixelWidth: pixelWidth)
      image = loaded
      loadedURL = url
      failed = loaded == nil
    }
  }
}
