import SwiftUI
import UIKit

struct FFRemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @StateObject private var loader = FFRemoteImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loader.load(url: url)
        }
    }
}

@MainActor
private final class FFRemoteImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    func load(url: URL?) async {
        image = nil
        guard let url else { return }

        if let cached = FFImageCache.shared.image(for: url) {
            image = cached
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            FFImageCache.shared.insert(image, for: url)
            self.image = image
        } catch {
            image = nil
        }
    }
}

private final class FFImageCache {
    static let shared = FFImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {}

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

enum FFRemoteImageCache {
    static func clearAll() {
        FFImageCache.shared.clear()
    }
}
