import AppKit
import Foundation
import SerialCore

@MainActor
final class SerialSession: ObservableObject, Identifiable {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    let id = UUID()

    @Published var configuration: SerialConfiguration
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var entries: [SerialLogEntry] = []
    @Published var displayMode: DataDisplayMode = .ascii
    @Published var sendFormat: SendFormat = .ascii
    @Published var lineEnding: LineEnding = .crlf
    @Published var showTimestamps = true
    @Published var showDirections = true
    @Published var showControlCodeChips = false
    @Published var autoScroll = true
    @Published var sendText = ""
    @Published private(set) var sendError: String?
    @Published private(set) var receivedBytes = 0
    @Published private(set) var transmittedBytes = 0
    @Published private(set) var loggingURL: URL?

    private let connection: SerialConnection
    private var logWriter: RealtimeLogWriter?
    private var hasSecurityScopedAccess = false
    private var pendingReceiveEntries: [SerialLogEntry] = []
    private var receiveFlushTask: Task<Void, Never>?
    private let maximumEntries = 5_000

    init(defaultPort: String?) {
        configuration = SerialConfiguration(path: defaultPort ?? "")
        connection = SerialConnection()

        connection.setHandlers(
            onData: { [weak self] data in
                Task { @MainActor [weak self] in
                    self?.receive(data)
                }
            },
            onClose: { [weak self] reason in
                Task { @MainActor [weak self] in
                    self?.handleUnexpectedClose(reason)
                }
            }
        )
    }

    var title: String {
        guard !configuration.path.isEmpty else { return "未接続" }
        let name = URL(fileURLWithPath: configuration.path).lastPathComponent
        return name.replacingOccurrences(of: "cu.", with: "")
    }

    var isConnected: Bool {
        connectionState == .connected
    }

    var isLogging: Bool {
        logWriter != nil
    }

    var statusText: String {
        switch connectionState {
        case .disconnected: "未接続"
        case .connecting: "接続中…"
        case .connected: "接続中"
        case .failed(let message): message
        }
    }

    func toggleConnection() {
        isConnected ? disconnect() : connect()
    }

    func connect() {
        guard !configuration.path.isEmpty else {
            recordSystemMessage("シリアルポートを選択してください。")
            connectionState = .failed("ポート未選択")
            return
        }

        connectionState = .connecting
        do {
            try connection.open(configuration: configuration)
            connectionState = .connected
            recordSystemMessage("\(configuration.path)へ接続しました（\(configuration.shortDescription)）。")
        } catch {
            let message = error.localizedDescription
            connectionState = .failed(message)
            recordSystemMessage(message)
        }
    }

    func disconnect() {
        connection.close()
        flushReceivedEntries()
        if connectionState != .disconnected {
            recordSystemMessage("接続を終了しました。")
        }
        connectionState = .disconnected
    }

    func send() {
        sendError = nil
        guard isConnected else {
            sendError = "先にシリアルポートへ接続してください。"
            return
        }

        do {
            let data = try SerialDataFormatter.data(
                from: sendText,
                format: sendFormat,
                lineEnding: lineEnding
            )
            try connection.send(data)
            transmittedBytes += data.count
            append(SerialLogEntry(direction: .transmitted, data: data))
            sendText = ""
        } catch {
            sendError = error.localizedDescription
            recordSystemMessage(error.localizedDescription)
        }
    }

    func clearEntries() {
        receiveFlushTask?.cancel()
        receiveFlushTask = nil
        pendingReceiveEntries.removeAll(keepingCapacity: true)
        entries.removeAll(keepingCapacity: true)
        receivedBytes = 0
        transmittedBytes = 0
    }

    func startLogging(to url: URL) {
        stopLogging()
        hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()

        do {
            logWriter = try RealtimeLogWriter(url: url)
            loggingURL = url
            recordSystemMessage("リアルタイムログの保存を開始しました。")
        } catch {
            if hasSecurityScopedAccess {
                url.stopAccessingSecurityScopedResource()
                hasSecurityScopedAccess = false
            }
            loggingURL = nil
            recordSystemMessage("ログファイルを開けませんでした：\(error.localizedDescription)")
        }
    }

    func stopLogging() {
        guard let currentURL = loggingURL else {
            logWriter?.close()
            logWriter = nil
            return
        }

        logWriter?.close()
        logWriter = nil
        if hasSecurityScopedAccess {
            currentURL.stopAccessingSecurityScopedResource()
            hasSecurityScopedAccess = false
        }
        loggingURL = nil
    }

    func shutdown() {
        connection.close()
        receiveFlushTask?.cancel()
        receiveFlushTask = nil
        flushReceivedEntries()
        stopLogging()
    }

    private func receive(_ data: Data) {
        receivedBytes += data.count
        let entry = SerialLogEntry(direction: .received, data: data)
        logWriter?.append(entry)
        pendingReceiveEntries.append(entry)

        guard receiveFlushTask == nil else { return }
        receiveFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            self?.flushReceivedEntries()
        }
    }

    private func handleUnexpectedClose(_ reason: String?) {
        guard connectionState != .disconnected else { return }
        flushReceivedEntries()
        connectionState = .failed(reason ?? "シリアルポートとの接続が終了しました。")
        recordSystemMessage(reason ?? "シリアルポートとの接続が終了しました。")
    }

    private func recordSystemMessage(_ message: String) {
        append(SerialLogEntry(direction: .system, data: Data(message.utf8)))
    }

    private func append(_ entry: SerialLogEntry) {
        entries.append(entry)
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        logWriter?.append(entry)
    }

    private func flushReceivedEntries() {
        receiveFlushTask?.cancel()
        receiveFlushTask = nil
        guard !pendingReceiveEntries.isEmpty else { return }

        entries.append(contentsOf: pendingReceiveEntries)
        pendingReceiveEntries.removeAll(keepingCapacity: true)
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
    }
}
