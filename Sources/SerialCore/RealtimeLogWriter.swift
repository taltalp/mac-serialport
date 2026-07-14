import Foundation

public final class RealtimeLogWriter: @unchecked Sendable {
    public let url: URL

    private let queue = DispatchQueue(label: "SerialMonitor.RealtimeLogWriter")
    private var handle: FileHandle?

    public init(url: URL) throws {
        self.url = url

        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        self.handle = handle
    }

    public func append(_ entry: SerialLogEntry) {
        let line = SerialDataFormatter.persistentLogLine(for: entry)
        guard let data = line.data(using: .utf8) else { return }

        queue.async { [weak self] in
            guard let self, let handle = self.handle else { return }
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()
            } catch {
                // UI側の接続処理を止めないため、書き込み失敗は次回の明示操作で扱う。
            }
        }
    }

    public func close() {
        queue.sync {
            guard let handle else { return }
            try? handle.synchronize()
            try? handle.close()
            self.handle = nil
        }
    }

    deinit {
        close()
    }
}
