import Darwin
import Dispatch
import Foundation
import Testing
@testable import SerialCore

@Suite("シリアル接続")
struct SerialConnectionTests {
    @Test("疑似端末へデータを送信できる")
    func sendToPseudoTerminal() throws {
        let terminal = try PseudoTerminal()
        defer { terminal.close() }

        let connection = SerialConnection(label: "send-test")
        defer { connection.close() }
        try connection.open(configuration: SerialConfiguration(path: terminal.slavePath))

        let expected = Data([0x73, 0x74, 0x61, 0x74, 0x75, 0x73, 0x0D, 0x0A])
        try connection.send(expected)

        var descriptor = pollfd(fd: terminal.master, events: Int16(POLLIN), revents: 0)
        #expect(poll(&descriptor, 1, 1_000) == 1)

        var buffer = [UInt8](repeating: 0, count: 64)
        let count = Darwin.read(terminal.master, &buffer, buffer.count)
        #expect(count == expected.count)
        #expect(Data(buffer.prefix(max(0, count))) == expected)
    }

    @Test("疑似端末からデータを受信できる")
    func receiveFromPseudoTerminal() throws {
        let terminal = try PseudoTerminal()
        defer { terminal.close() }

        let received = LockedData()
        let semaphore = DispatchSemaphore(value: 0)
        let connection = SerialConnection(label: "receive-test")
        defer { connection.close() }
        connection.setHandlers(
            onData: { data in
                received.set(data)
                semaphore.signal()
            },
            onClose: nil
        )
        try connection.open(configuration: SerialConfiguration(path: terminal.slavePath))

        let expected = Data([0x7E, 0x00, 0xFF, 0x0D, 0x0A])
        let writeCount = expected.withUnsafeBytes { buffer in
            Darwin.write(terminal.master, buffer.baseAddress, buffer.count)
        }
        #expect(writeCount == expected.count)
        #expect(semaphore.wait(timeout: .now() + 1) == .success)
        #expect(received.value == expected)
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }
}

private final class PseudoTerminal {
    let master: Int32
    let slavePath: String

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw POSIXError(.ENODEV)
        }
        guard let path = ttyname(slave) else {
            Darwin.close(master)
            Darwin.close(slave)
            throw POSIXError(.ENODEV)
        }

        self.master = master
        self.slavePath = String(cString: path)
        Darwin.close(slave)
    }

    func close() {
        Darwin.close(master)
    }
}
