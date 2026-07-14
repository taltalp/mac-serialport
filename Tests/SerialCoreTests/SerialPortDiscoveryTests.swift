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

    @Test("USBシリアル番号が同じ機器をパス変更後も識別する")
    func identifyUSBDeviceAcrossPathChanges() {
        let original = SerialPortInfo(
            path: "/dev/cu.usbmodem101",
            productName: "Arduino Uno",
            manufacturer: "Arduino",
            vendorID: 0x2341,
            productID: 0x0043,
            serialNumber: "ABC123"
        )
        let reconnected = SerialPortInfo(
            path: "/dev/cu.usbmodem202",
            productName: "Arduino Uno",
            manufacturer: "Arduino",
            vendorID: 0x2341,
            productID: 0x0043,
            serialNumber: "ABC123"
        )
        let anotherDevice = SerialPortInfo(
            path: "/dev/cu.usbmodem303",
            vendorID: 0x2341,
            productID: 0x0043,
            serialNumber: "XYZ789"
        )

        #expect(original.representsSameDevice(as: reconnected))
        #expect(!original.representsSameDevice(as: anotherDevice))
        #expect(original.menuTitle == "Arduino Uno — cu.usbmodem101")
        #expect(original.vendorProductText == "2341:0043")
    }

    @Test("シリアル番号がないUSB機器は接続位置で識別する")
    func identifyUSBDeviceByLocation() {
        let original = SerialPortInfo(
            path: "/dev/cu.usbserial-01",
            vendorID: 0x1A86,
            productID: 0x7523,
            locationID: 0x0010_0000
        )
        let reconnected = SerialPortInfo(
            path: "/dev/cu.usbserial-02",
            vendorID: 0x1A86,
            productID: 0x7523,
            locationID: 0x0010_0000
        )

        #expect(original.representsSameDevice(as: reconnected))
    }
}
