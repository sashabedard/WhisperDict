import Foundation

@MainActor
final class HistoryManager {
    static let shared = HistoryManager()
    private(set) var items: [String] = []
    private let maxItems = 8

    func add(_ text: String) {
        items.insert(text, at: 0)
        if items.count > maxItems { items = Array(items.prefix(maxItems)) }
    }
}
