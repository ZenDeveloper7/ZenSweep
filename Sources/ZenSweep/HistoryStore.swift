import Foundation

@MainActor protocol HistoryStore {
    func load() -> [ActivityRecord]
    func save(_ records: [ActivityRecord]) throws
}
@MainActor struct DefaultsHistoryStore: HistoryStore {
    let defaults: UserDefaults
    let key: String
    init(defaults: UserDefaults = .standard, key: String = "ZenSweep.history") { self.defaults = defaults; self.key = key }
    func load() -> [ActivityRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ActivityRecord].self, from: data)) ?? []
    }
    func save(_ records: [ActivityRecord]) throws { defaults.set(try JSONEncoder().encode(records), forKey: key) }
}
