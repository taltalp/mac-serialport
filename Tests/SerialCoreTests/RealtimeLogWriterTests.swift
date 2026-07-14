import Foundation
import Testing
@testable import SerialCore

@Suite("リアルタイムログ")
struct RealtimeLogWriterTests {
    @Test("受信イベントをファイルへ即時保存する")
    func appendEntry() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("log")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try RealtimeLogWriter(url: url)
        writer.append(SerialLogEntry(
            direction: .received,
            data: Data([0x4F, 0x4B, 0x0D, 0x0A])
        ))
        writer.close()

        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("RX"))
        #expect(content.contains("OK\\r\\n"))
        #expect(content.contains("4F 4B 0D 0A"))
    }
}
