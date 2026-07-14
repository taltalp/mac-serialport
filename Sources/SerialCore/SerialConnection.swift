import Darwin
import Dispatch
import Foundation

public enum SerialConnectionError: LocalizedError {
    case noPortSelected
    case openFailed(String, Int32)
    case configurationFailed(String)
    case unsupportedBaudRate(Int)
    case notConnected
    case writeFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .noPortSelected:
            "シリアルポートが選択されていません。"
        case .openFailed(let path, let code):
            "\(path)を開けませんでした（\(String(cString: strerror(code)))）。"
        case .configurationFailed(let reason):
            "シリアル設定を適用できませんでした（\(reason)）。"
        case .unsupportedBaudRate(let baudRate):
            "ボーレート\(baudRate)は現在のバックエンドでサポートされていません。"
        case .notConnected:
            "シリアルポートに接続されていません。"
        case .writeFailed(let code):
            "送信に失敗しました（\(String(cString: strerror(code)))）。"
        }
    }
}

public final class SerialConnection: @unchecked Sendable {
    public typealias DataHandler = @Sendable (Data) -> Void
    public typealias CloseHandler = @Sendable (String?) -> Void

    private let stateLock = NSLock()
    private let readQueue: DispatchQueue
    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var dataHandler: DataHandler?
    private var closeHandler: CloseHandler?

    public init(label: String = UUID().uuidString) {
        readQueue = DispatchQueue(
            label: "SerialMonitor.SerialConnection.\(label)",
            qos: .userInitiated
        )
    }

    public var isOpen: Bool {
        stateLock.withLock { fileDescriptor >= 0 }
    }

    public func setHandlers(onData: DataHandler?, onClose: CloseHandler?) {
        stateLock.withLock {
            dataHandler = onData
            closeHandler = onClose
        }
    }

    public func open(configuration: SerialConfiguration) throws {
        guard !configuration.path.isEmpty else {
            throw SerialConnectionError.noPortSelected
        }
        close(notify: false)

        let descriptor = Darwin.open(
            configuration.path,
            O_RDWR | O_NOCTTY | O_NONBLOCK
        )
        guard descriptor >= 0 else {
            throw SerialConnectionError.openFailed(configuration.path, errno)
        }

        do {
            try Self.configure(descriptor: descriptor, configuration: configuration)
        } catch {
            Darwin.close(descriptor)
            throw error
        }

        let source = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: readQueue
        )
        source.setEventHandler { [weak self] in
            self?.drainAvailableData()
        }

        stateLock.withLock {
            fileDescriptor = descriptor
            readSource = source
        }
        source.resume()
    }

    public func close() {
        close(notify: false)
    }

    public func send(_ data: Data) throws {
        let descriptor = stateLock.withLock { fileDescriptor }
        guard descriptor >= 0 else { throw SerialConnectionError.notConnected }
        guard !data.isEmpty else { return }

        var written = 0
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            while written < rawBuffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )
                if result > 0 {
                    written += result
                } else if result < 0, errno == EINTR {
                    continue
                } else {
                    throw SerialConnectionError.writeFailed(errno)
                }
            }
        }
    }

    private func drainAvailableData() {
        let descriptor = stateLock.withLock { fileDescriptor }
        guard descriptor >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                let data = Data(buffer.prefix(count))
                let handler = stateLock.withLock { dataHandler }
                handler?(data)
                continue
            }
            if count == 0 {
                close(notify: true, reason: "デバイスとの接続が終了しました。")
            } else if errno == EINTR {
                continue
            } else if errno != EAGAIN && errno != EWOULDBLOCK {
                let message = String(cString: strerror(errno))
                close(notify: true, reason: message)
            }
            break
        }
    }

    private func close(notify: Bool, reason: String? = nil) {
        let values = stateLock.withLock { () -> (Int32, DispatchSourceRead?, CloseHandler?) in
            let values = (fileDescriptor, readSource, closeHandler)
            fileDescriptor = -1
            readSource = nil
            return values
        }

        values.1?.cancel()
        if values.0 >= 0 {
            Darwin.close(values.0)
        }
        if notify {
            values.2?(reason)
        }
    }

    private static func configure(
        descriptor: Int32,
        configuration: SerialConfiguration
    ) throws {
        var options = termios()
        guard tcgetattr(descriptor, &options) == 0 else {
            throw SerialConnectionError.configurationFailed(String(cString: strerror(errno)))
        }

        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(CSIZE)

        switch configuration.dataBits {
        case 5: options.c_cflag |= tcflag_t(CS5)
        case 6: options.c_cflag |= tcflag_t(CS6)
        case 7: options.c_cflag |= tcflag_t(CS7)
        default: options.c_cflag |= tcflag_t(CS8)
        }

        switch configuration.parity {
        case .none:
            options.c_cflag &= ~tcflag_t(PARENB | PARODD)
        case .even:
            options.c_cflag |= tcflag_t(PARENB)
            options.c_cflag &= ~tcflag_t(PARODD)
        case .odd:
            options.c_cflag |= tcflag_t(PARENB | PARODD)
        }

        if configuration.stopBits == 2 {
            options.c_cflag |= tcflag_t(CSTOPB)
        } else {
            options.c_cflag &= ~tcflag_t(CSTOPB)
        }

        options.c_cflag &= ~tcflag_t(CRTSCTS)
        options.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        switch configuration.flowControl {
        case .none:
            break
        case .hardware:
            options.c_cflag |= tcflag_t(CRTSCTS)
        case .software:
            options.c_iflag |= tcflag_t(IXON | IXOFF)
        }

        guard let speed = speed(for: configuration.baudRate) else {
            throw SerialConnectionError.unsupportedBaudRate(configuration.baudRate)
        }
        guard cfsetispeed(&options, speed) == 0, cfsetospeed(&options, speed) == 0 else {
            throw SerialConnectionError.configurationFailed(String(cString: strerror(errno)))
        }

        // With O_NONBLOCK, VMIN=1 makes an empty read return EAGAIN instead of
        // zero. A zero result can then be treated as an actual EOF/disconnect.
        options.c_cc.16 = 1 // VMIN
        options.c_cc.17 = 0 // VTIME

        guard tcsetattr(descriptor, TCSANOW, &options) == 0 else {
            throw SerialConnectionError.configurationFailed(String(cString: strerror(errno)))
        }
        tcflush(descriptor, TCIOFLUSH)
    }

    private static func speed(for baudRate: Int) -> speed_t? {
        switch baudRate {
        case 300: speed_t(B300)
        case 600: speed_t(B600)
        case 1_200: speed_t(B1200)
        case 2_400: speed_t(B2400)
        case 4_800: speed_t(B4800)
        case 9_600: speed_t(B9600)
        case 14_400: speed_t(B14400)
        case 19_200: speed_t(B19200)
        case 28_800: speed_t(B28800)
        case 38_400: speed_t(B38400)
        case 57_600: speed_t(B57600)
        case 115_200: speed_t(B115200)
        case 230_400: speed_t(B230400)
        default: nil
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
