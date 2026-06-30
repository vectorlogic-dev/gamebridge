import Foundation
import Combine

/// Owns the list of bottles and persists them as JSON in Application Support.
/// The bottle *directories* live wherever the user chose; this only tracks them.
@MainActor
final class BottleStore: ObservableObject {
    @Published var bottles: [Bottle] = []
    @Published var selectedWinePath: String = WineLocator.detect().first?.winePath ?? ""

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.fileURL = appSupport.appendingPathComponent("bottles.json")
        load()
    }

    /// Default location for a brand-new bottle's prefix.
    func defaultPrefixURL(for name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameBridge/Bottles/\(safe)", isDirectory: true)
    }

    func add(_ bottle: Bottle) {
        bottles.append(bottle)
        save()
    }

    func update(_ bottle: Bottle) {
        guard let idx = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[idx] = bottle
        save()
    }

    func remove(_ bottle: Bottle, deleteFiles: Bool) {
        bottles.removeAll { $0.id == bottle.id }
        if deleteFiles {
            try? FileManager.default.removeItem(at: bottle.prefixURL)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            bottles = try JSONDecoder().decode([Bottle].self, from: data)
        } catch {
            bottles = []
            ErrorLogger.shared.log(error, source: "bottle", context: "decode bottles.json")
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try enc.encode(bottles)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            ErrorLogger.shared.log(error, source: "bottle", context: "write bottles.json")
        }
    }
}
