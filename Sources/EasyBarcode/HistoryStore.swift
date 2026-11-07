import BarcodeKit
import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let digits: String
    let format: BarcodeFormat
    let createdAt: Date
    var note: String?
    var imagePath: String?

    init(
        id: UUID,
        digits: String,
        format: BarcodeFormat,
        createdAt: Date,
        note: String? = nil,
        imagePath: String? = nil
    ) {
        self.id = id
        self.digits = digits
        self.format = format
        self.createdAt = createdAt
        self.note = note
        self.imagePath = imagePath
    }
}

/// Persists generated barcodes and their image files. Images live in a
/// user-configurable directory; entries without a file are regenerated on
/// launch so older history keeps working.
final class HistoryStore {
    static let shared = HistoryStore()

    private(set) var entries: [HistoryEntry] = []

    private let defaultsKey = "EasyBarcode.history.v1"
    private let imagesDirectoryKey = "EasyBarcode.historyImagesDirectory"
    private let maxEntries = 50

    private init() {
        load()
        backfillImagesIfNeeded()
    }

    // MARK: - Image directory

    static var defaultImagesDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("EasyBarcode/History", isDirectory: true)
    }

    var imagesDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: imagesDirectoryKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Self.defaultImagesDirectory
    }

    var imagesDirectoryDisplayPath: String {
        abbreviate(imagesDirectory.path)
    }

    func setImagesDirectory(_ url: URL) {
        let standardized = url.standardizedFileURL
        UserDefaults.standard.set(standardized.path, forKey: imagesDirectoryKey)
        ensureImagesDirectory()
        migrateImages(to: standardized)
    }

    func resetImagesDirectory() {
        setImagesDirectory(Self.defaultImagesDirectory)
    }

    // MARK: - Entries

    func record(digits: String, format: BarcodeFormat) {
        var entry = HistoryEntry(id: UUID(), digits: digits, format: format, createdAt: Date())
        attachImage(to: &entry)

        if let duplicate = entries.first(where: { $0.digits == digits && $0.format == format }) {
            removeImage(for: duplicate)
        }
        entries.removeAll { $0.digits == digits && $0.format == format }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            let removed = entries.suffix(entries.count - maxEntries)
            removed.forEach(removeImage)
            entries.removeLast(entries.count - maxEntries)
        }
        save()
    }

    func updateNote(id: UUID, note: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].note = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func delete(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        removeImage(for: entries[index])
        entries.remove(at: index)
        save()
    }

    func clear() {
        entries.forEach(removeImage)
        entries.removeAll()
        save()
    }

    // MARK: - Images

    private func ensureImagesDirectory() {
        try? FileManager.default.createDirectory(
            at: imagesDirectory,
            withIntermediateDirectories: true
        )
    }

    private func attachImage(to entry: inout HistoryEntry) {
        let payload = BarcodePayloadBuilder.make(from: entry.digits, requested: entry.format)
        guard payload.isValid,
              let data = BarcodeImageRenderer.pngData(for: payload, targetWidth: 1200) else {
            entry.imagePath = nil
            return
        }

        ensureImagesDirectory()
        let url = imagesDirectory.appendingPathComponent("\(entry.id.uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            entry.imagePath = url.path
        } catch {
            entry.imagePath = nil
        }
    }

    private func backfillImagesIfNeeded() {
        ensureImagesDirectory()
        var changed = false

        for index in entries.indices {
            if let path = entries[index].imagePath,
               FileManager.default.fileExists(atPath: path) {
                continue
            }
            attachImage(to: &entries[index])
            changed = true
        }

        if changed {
            save()
        }
    }

    private func migrateImages(to directory: URL) {
        ensureImagesDirectory()
        var changed = false

        for index in entries.indices {
            var entry = entries[index]
            let destination = directory.appendingPathComponent("\(entry.id.uuidString).png")

            if let path = entry.imagePath, FileManager.default.fileExists(atPath: path) {
                if path != destination.path {
                    try? FileManager.default.removeItem(at: destination)
                    do {
                        try FileManager.default.copyItem(
                            at: URL(fileURLWithPath: path),
                            to: destination
                        )
                        entry.imagePath = destination.path
                    } catch {
                        // Keep the old path if the copy fails.
                    }
                } else {
                    entry.imagePath = destination.path
                }
            } else {
                attachImage(to: &entry)
            }

            entries[index] = entry
            changed = true
        }

        if changed {
            save()
        }
    }

    private func removeImage(for entry: HistoryEntry) {
        if let path = entry.imagePath {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return
        }
        entries = Array(decoded.prefix(maxEntries))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
