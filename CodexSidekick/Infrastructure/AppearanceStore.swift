import Foundation

struct AppearanceStore {
    private let defaultsKey = "codex.sidekick.appearance"
    private let defaults = UserDefaults.standard

    func load() -> SidekickAppearanceSettings? {
        guard let data = defaults.data(forKey: defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SidekickAppearanceSettings.self, from: data)
    }

    func save(_ settings: SidekickAppearanceSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: defaultsKey)
    }
}
