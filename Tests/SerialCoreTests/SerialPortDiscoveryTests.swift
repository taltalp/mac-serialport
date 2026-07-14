import Foundation
import Testing
@testable import SerialCore

@Suite("シリアルポート検出")
struct SerialPortDiscoveryTests {
    @Test("cuデバイスのみを列挙する")
    func onlyCalloutDevices() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["cu.usbmodem1101", "cu.usbserial-01", "tty.usbmodem1101", "random"] {
            FileManager.default.createFile(
                atPath: directory.appendingPathComponent(name).path,
                contents: Data()
            )
        }

        let result = SerialPortDiscovery.availablePorts(in: directory.path)
        #expect(result.map { URL(fileURLWithPath: $0).lastPathComponent } == [
            "cu.usbmodem1101",
            "cu.usbserial-01"
        ])
    }
}
