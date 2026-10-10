import Darwin
import Foundation
import SerialCore
import Testing
@testable import SerialMonitor

@Suite("受信ログのセッション統合")
@MainActor
struct SerialSessionTests {
    @Test("画面更新をまたいだ受信を結合し消去・再接続後は新しい行を始める")
    func assemblesLinesAcrossUIUpdates() async throws {
        let terminal = try SessionPseudoTerminal()
        defer { terminal.close() }
        let session = SerialSession(defaultPort: terminal.slavePath)
        defer { session.shutdown() }
        session.connect()
        try #require(session.isConnected)

        try terminal.write("first")
        try await waitUntil { receivedEntries(session).count == 1 }
        let first = try #require(receivedEntries(session).first)
        #expect(first.data == Data("first".utf8))

        try terminal.write(" line\r\nsecond\r")
        try await waitUntil { receivedEntries(session).count == 2 }
        #expect(receivedEntries(session).map(\.data) == [Data("first line\r\n".utf8), Data("second\r".utf8)])
        #expect(receivedEntries(session).first?.id == first.id)
        #expect(receivedEntries(session).first?.date == first.date)

        try terminal.write("\n")
        try await waitUntil { receivedEntries(session).last?.data == Data("second\r\n".utf8) }
        #expect(receivedEntries(session).count == 2)
        #expect(session.receivedBytes == Data("first line\r\nsecond\r\n".utf8).count)

        session.clearEntries()
        #expect(session.entries.isEmpty)
        #expect(session.receivedBytes == 0)
        try terminal.write("partial")
        try await waitUntil { receivedEntries(session).count == 1 }

        session.disconnect()
        session.connect()
        try #require(session.isConnected)
        try terminal.write("new\r\n")
        try await waitUntil { receivedEntries(session).count == 2 }
        #expect(receivedEntries(session).map(\.data) == [Data("partial".utf8), Data("new\r\n".utf8)])
    }

    @Test("画面で結合した受信データも保存ファイルには各受信を一度だけ記録する")
    func keepsImmediateFileLogging() async throws {
        let terminal = try SessionPseudoTerminal()
        defer { terminal.close() }
        let session = SerialSession(defaultPort: terminal.slavePath)
        defer { session.shutdown() }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("serial-session-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }

        session.connect()
        try #require(session.isConnected)
        session.startLogging(to: url)
        try #require(session.isLogging)
        try terminal.write("first")
        try await waitUntil { receivedEntries(session).count == 1 }
        try terminal.write(" second\r\n")
        try await waitUntil { receivedEntries(session).first?.data == Data("first second\r\n".utf8) }
        session.stopLogging()

        let log = try String(contentsOf: url, encoding: .utf8)
        let receives = log.split(separator: "\n").filter { $0.contains("  RX  ") }
        #expect(receives.count == 2)
        #expect(receives.first?.contains("first    [66 69 72 73 74]") == true)
        #expect(receives.last?.contains(" second\\r\\n    [20 73 65 63 6F 6E 64 0D 0A]") == true)
    }

    private func receivedEntries(_ session: SerialSession) -> [SerialLogEntry] {
        session.entries.filter { $0.direction == .received }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "受信ログが時間内に更新されませんでした")
    }
}

private final class SessionPseudoTerminal {
    let master: Int32
    let slavePath: String

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw POSIXError(.ENODEV)
        }
        defer { Darwin.close(slave) }
        guard let path = ttyname(slave) else {
            Darwin.close(master)
            throw POSIXError(.ENODEV)
        }
        self.master = master
        slavePath = String(cString: path)
    }

    func write(_ text: String) throws {
        let data = Data(text.utf8)
        let count = data.withUnsafeBytes { buffer in
            Darwin.write(master, buffer.baseAddress, buffer.count)
        }
        try #require(count == data.count)
    }

    func close() {
        Darwin.close(master)
    }
}
