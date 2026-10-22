import AppKit
import ImageIO
import ScratchCore

/// Decodes the previews of the images that notes hold, on a background queue, and keeps them (plan 5, task 4).
///
/// - **Never on the main thread.** `image(for:id:maxPixelSize:completion:)` answers from the cache, or starts a thumbnail
///   on a private serial queue (`CGImageSourceCreateThumbnailAtIndex`, which reads only what the size needs of a JPEG)
///   and answers nil. The requests are served in the order they came, so the images on screen, which the styler asks for
///   first, are decoded first.
/// - **A preview is for an id.** The cache holds the biggest thumbnail of each image that was asked for, with the size it
///   was made for, and a request for a size that the cache holds already is answered at once. A request for a bigger size
///   (the window got wider) decodes again, and the layout manager draws the smaller one until then.
/// - **Arrivals are announced.** `onChange` is called on the main thread with the id and whether the image could be decoded,
///   before the completions of the requests are, and is where the editor invalidates the display of the lines of the
///   image or, when it could not be decoded, draws them as a missing attachment. A request that nobody waits for (the
///   layout manager asks for what it finds missing when it draws, which is how a preview that the cache gave up recovers)
///   is `request(for:id:maxPixelSize:)`.
///
/// The class is not on the main actor: the layout manager, which is not either, draws from it. Everything is thread-safe.
nonisolated final class AttachmentPreviews: @unchecked Sendable {
    /// A decoded thumbnail, and the size of its longer side that it was asked for.
    nonisolated private final class Entry {
        let image: CGImage
        let maxPixelSize: Int

        init(image: CGImage, maxPixelSize: Int) {
            self.image = image
            self.maxPixelSize = maxPixelSize
        }
    }

    /// A `CGImage` that crosses from the decoding queue to the main thread. Images are immutable.
    nonisolated private struct ImageBox: @unchecked Sendable {
        let image: CGImage?
    }

    /// Called on the main thread when a request is done, with the id and whether there is an image for it now.
    var onChange: (@MainActor (AttachmentID, Bool) -> Void)?

    private let queue = DispatchQueue(label: "io.github.ldellisola.Scratch.previews", qos: .userInitiated)
    private let cache = NSCache<NSString, Entry>()
    private let lock = NSLock()
    /// The requests that wait for the queue or are being decoded, by `key(id, size)`, with who wants the answer.
    private var pending: [String: [@MainActor (NSImage?) -> Void]] = [:]
    /// The images that could not be decoded: asked for no more.
    private var failed: Set<String> = []

    /// About 100 MB of thumbnails, at four bytes a pixel.
    private static let cacheLimit = 100 * 1_024 * 1_024

    init() {
        cache.totalCostLimit = Self.cacheLimit
    }

    // MARK: Asking

    /// The preview of the image at `url` for `id`, at least `maxPixelSize` pixels on its longer side (rounded up to a
    /// multiple of 64, so that the sizes of a window that is being resized share a thumbnail), or nil.
    ///
    /// Nil starts the decoding unless it is under way or failed before, and `completion` is called on the main thread
    /// with the image, or nil when the image could not be decoded. The image that is returned or given is made from the
    /// thumbnail for each call, so it can be used on the main thread only.
    @discardableResult
    func image(
        for url: URL, id: AttachmentID, maxPixelSize: Int, completion: @escaping @MainActor (NSImage?) -> Void
    ) -> NSImage? {
        let wanted = Self.quantised(maxPixelSize)
        if let cached = cachedImage(forID: id, minPixelSize: wanted) { return cached }
        let key = Self.key(id, wanted)
        let shouldDecode: Bool? = lock.withLock {
            if failed.contains(id.rawValue) { return nil }
            let isRunning = pending[key] != nil
            pending[key, default: []].append(completion)
            return !isRunning
        }
        // An image that failed before is not tried again, and nobody is told again: the first failure was announced.
        guard shouldDecode == true else { return nil }

        queue.async { [self] in
            let decoded = Self.decode(url, maxPixelSize: wanted)
            let completions = lock.withLock { () -> [@MainActor (NSImage?) -> Void] in
                if let decoded {
                    cache.setObject(
                        Entry(image: decoded, maxPixelSize: wanted), forKey: id.rawValue as NSString,
                        cost: decoded.width * decoded.height * 4)
                } else {
                    failed.insert(id.rawValue)
                }
                return pending.removeValue(forKey: key) ?? []
            }
            let box = ImageBox(image: decoded)
            DispatchQueue.main.async { [self] in
                MainActor.assumeIsolated {
                    let image = box.image.map { Self.nsImage($0) }
                    onChange?(id, image != nil)
                    for completion in completions { completion(image) }
                }
            }
        }
        return nil
    }

    /// `image(for:id:maxPixelSize:completion:)` for a caller that learns of the result from `onChange`.
    func request(for url: URL, id: AttachmentID, maxPixelSize: Int) {
        _ = image(for: url, id: id, maxPixelSize: maxPixelSize) { _ in }
    }

    /// The preview of `id` that is in the cache, if it was made for at least `minPixelSize`, whatever its size is. What the
    /// layout manager draws, so one call is cheap and starts nothing.
    func cachedImage(forID id: AttachmentID, minPixelSize: Int) -> NSImage? {
        guard let entry = cache.object(forKey: id.rawValue as NSString), entry.maxPixelSize >= minPixelSize else {
            return nil
        }
        return Self.nsImage(entry.image)
    }

    /// How many decodings are waiting or under way.
    var pendingCount: Int {
        lock.withLock { pending.count }
    }

    /// Forgets what is known of `id`: its thumbnail and that it could not be decoded. For a file that changed.
    func discard(_ id: AttachmentID) {
        cache.removeObject(forKey: id.rawValue as NSString)
        lock.withLock { _ = failed.remove(id.rawValue) }
    }

    // MARK: Decoding

    /// The thumbnail of the image at `url`, with its longer side at most `maxPixelSize` pixels, rotated as the image says,
    /// or nil when the file is not an image that can be decoded.
    private static func decode(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// `size` rounded up to a multiple of 64, and at least 64.
    private static func quantised(_ size: Int) -> Int {
        max(64, (size + 63) / 64 * 64)
    }

    private static func key(_ id: AttachmentID, _ size: Int) -> String {
        "\(id.rawValue)#\(size)"
    }

    private static func nsImage(_ image: CGImage) -> NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
