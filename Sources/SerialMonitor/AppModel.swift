import Foundation
import SerialCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [SerialSession] = []
    @Published var selectedSessionID: UUID?
    @Published private(set) var availablePorts: [SerialPortInfo] = []
    let sendCommandStore = SendCommandStore()

    init() {
        refreshPorts()
        addSession()
    }

    var selectedSession: SerialSession? {
        guard let selectedSessionID else { return sessions.first }
        return sessions.first { $0.id == selectedSessionID } ?? sessions.first
    }

    func addSession() {
        let session = SerialSession(defaultPort: firstUnusedPort())
        sessions.append(session)
        selectedSessionID = session.id
    }

    func closeSession(_ id: UUID) {
        guard sessions.count > 1, let index = sessions.firstIndex(where: { $0.id == id }) else {
            return
        }

        sessions[index].shutdown()
        sessions.remove(at: index)
        if selectedSessionID == id {
            selectedSessionID = sessions[min(index, sessions.count - 1)].id
        }
    }

    func refreshPorts() {
        availablePorts = SerialPortDiscovery.availablePortInfos()
        for session in sessions where session.configuration.path.isEmpty && !session.isConnected {
            session.configuration.path = firstUnusedPort() ?? availablePorts.first?.path ?? ""
        }
        sessions.forEach { $0.updateAvailablePorts(availablePorts) }
    }

    func closeAll() {
        sessions.forEach { $0.shutdown() }
    }

    private func firstUnusedPort() -> String? {
        let used = Set(sessions.map(\.configuration.path).filter { !$0.isEmpty })
        return availablePorts.first { !used.contains($0.path) }?.path ?? availablePorts.first?.path
    }
}
