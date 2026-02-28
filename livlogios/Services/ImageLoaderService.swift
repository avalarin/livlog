//
//  ImageLoaderService.swift
//  livlogios
//

import UIKit

// MARK: - AsyncSemaphore

private actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) { self.count = count }

    func wait() async {
        if count > 0 {
            count -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if waiters.isEmpty {
            count += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

// MARK: - Cache Entry

private final class CachedImageEntry: @unchecked Sendable {
    let image: UIImage
    let hash: String?

    init(_ image: UIImage, hash: String?) {
        self.image = image
        self.hash = hash
    }
}

// MARK: - ImageLoaderService

actor ImageLoaderService {
    static let shared = ImageLoaderService()

    private let cache = NSCache<NSString, CachedImageEntry>()
    private let semaphore = AsyncSemaphore(count: 4)
    private var inFlightTasks: [String: Task<UIImage, Error>] = [:]

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    func load(id: String, hash: String?) async throws -> UIImage {
        // 1. Cache hit — validate hash
        if let entry = cache.object(forKey: id as NSString) {
            if hash == nil || entry.hash == hash {
                return entry.image
            }
            // Hash mismatch — evict and re-fetch
            cache.removeObject(forKey: id as NSString)
        }

        // 2. In-flight deduplication: reuse existing download for same ID
        if let existing = inFlightTasks[id] {
            return try await existing.value
        }

        // 3. Create download task with throttle
        let capturedSemaphore = semaphore
        let downloadTask = Task<UIImage, Error> {
            await capturedSemaphore.wait()
            do {
                let data = try await EntryService.shared.getImage(imageID: id)
                guard let image = UIImage(data: data) else {
                    await capturedSemaphore.signal()
                    throw URLError(.cannotDecodeContentData)
                }
                await capturedSemaphore.signal()
                return image
            } catch {
                await capturedSemaphore.signal()
                throw error
            }
        }
        inFlightTasks[id] = downloadTask

        do {
            let image = try await downloadTask.value
            inFlightTasks.removeValue(forKey: id)
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(CachedImageEntry(image, hash: hash), forKey: id as NSString, cost: cost)
            return image
        } catch {
            inFlightTasks.removeValue(forKey: id)
            throw error
        }
    }
}
