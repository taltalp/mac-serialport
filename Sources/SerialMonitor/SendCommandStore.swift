import Foundation
import SerialCore

struct SendPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var text: String
    var format: SendFormat
    var lineEnding: LineEnding

    init(
        id: UUID = UUID(),
        name: String,
        text: String,
        format: SendFormat,
        lineEnding: LineEnding
    ) {
        self.id = id
        self.name = name
        self.text = text
        self.format = format
        self.lineEnding = lineEnding
    }
}

@MainActor
final class SendCommandStore: ObservableObject {
    @Published private(set) var presets: [SendPreset] = [] {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let storageKey = "SerialMonitor.SendPresets.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SendPreset].self, from: data)
        else { return }
        presets = decoded
    }

    func add(
        name: String,
        text: String,
        format: SendFormat,
        lineEnding: LineEnding
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !text.isEmpty else { return }

        let preset = SendPreset(
            name: trimmedName,
            text: text,
            format: format,
            lineEnding: lineEnding
        )
        if let index = presets.firstIndex(where: {
            $0.name.compare(trimmedName, options: .caseInsensitive) == .orderedSame
        }) {
            presets[index] = preset
        } else {
            presets.append(preset)
            presets.sort {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    func remove(_ preset: SendPreset) {
        presets.removeAll { $0.id == preset.id }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
