import AppKit
import Foundation
import SerialCore

enum LogDirectionFilter: String, CaseIterable, Identifiable {
    case all
    case received
    case transmitted
    case system

    var id: Self { self }

    var displayName: String {
        switch self {
        case .all: "すべて"
        case .received: "RX"
        case .transmitted: "TX"
        case .system: "SYS"
        }
    }

    func includes(_ direction: SerialDirection) -> Bool {
        switch self {
        case .all: true
        case .received: direction == .received
        case .transmitted: direction == .transmitted
        case .system: direction == .system
        }
    }
}

struct SendHistoryEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let text: String
    let format: SendFormat
    let lineEnding: LineEnding

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        text: String,
        format: SendFormat,
        lineEnding: LineEnding
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.format = format
        self.lineEnding = lineEnding
    }
}

@MainActor
final class SerialSession: ObservableObject, Identifiable {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed(String)
    }

    let id = UUID()

    @Published var configuration: SerialConfiguration
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var currentPortInfo: SerialPortInfo?
    @Published private(set) var entries: [SerialLogEntry] = []
    @Published var displayMode: DataDisplayMode = .ascii
    @Published var sendFormat: SendFormat = .ascii
    @Published var lineEnding: LineEnding = .crlf
    @Published var showTimestamps = true
    @Published var showDirections = true
    @Published var showControlCodeChips = false
    @Published var autoScroll = true
    @Published var logSearchText = ""
    @Published var logDirectionFilter: LogDirectionFilter = .all
    @Published var showOnlySearchMatches = false
    @Published var sendText = ""
    @Published private(set) var sendHistory: [SendHistoryEntry] = []
    @Published var autoReconnect = false {
        didSet {
            guard !autoReconnect, reconnectPending else { return }
            reconnectPending = false
            if connectionState == .reconnecting {
                connectionState = .disconnected
                recordSystemMessage("自動再接続を停止しました。")
            }
        }
    }
    @Published private(set) var sendError: String?
    @Published private(set) var receivedBytes = 0
    @Published private(set) var transmittedBytes = 0
    @Published private(set) var loggingURL: URL?

    private let connection: SerialConnection
    private var logWriter: RealtimeLogWriter?
    private var hasSecurityScopedAccess = false
    private var pendingReceiveEntries: [SerialLogEntry] = []
    private var receiveFlushTask: Task<Void, Never>?
    private var reconnectTarget: SerialPortInfo?
    private var reconnectPending = false
    private let maximumEntries = 5_000
    private let maximumSendHistoryEntries = 50

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
        if let currentPortInfo, currentPortInfo.hasUSBMetadata {
            return currentPortInfo.deviceName
        }
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
        case .reconnecting: "自動再接続を待機中…"
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

        reconnectPending = false
        reconnectTarget = currentPortInfo ?? SerialPortInfo(path: configuration.path)
        connectionState = .connecting
        do {
            try connection.open(configuration: configuration)
            connectionState = .connected
            recordSystemMessage("\(configuration.path)へ接続しました（\(configuration.shortDescription)）。")
        } catch {
            let message = error.localizedDescription
            recordSystemMessage(message)
            if autoReconnect {
                reconnectPending = true
                connectionState = .reconnecting
                recordSystemMessage("デバイスが利用可能になり次第、自動的に再接続します。")
            } else {
                connectionState = .failed(message)
            }
        }
    }

    func disconnect() {
        reconnectPending = false
        connection.close()
        flushReceivedEntries()
        if connectionState != .disconnected {
            recordSystemMessage("接続を終了しました。")
        }
        connectionState = .disconnected
    }

    func updateAvailablePorts(_ ports: [SerialPortInfo]) {
        let selectedPort = ports.first { $0.path == configuration.path }
        if let selectedPort {
            currentPortInfo = selectedPort
            if isConnected {
                reconnectTarget = selectedPort
            }
        } else if !configuration.path.isEmpty, currentPortInfo == nil {
            currentPortInfo = SerialPortInfo(path: configuration.path)
        }

        if isConnected, selectedPort == nil {
            connection.close()
            handleUnexpectedClose("デバイスが取り外されました。")
        }

        guard autoReconnect, reconnectPending, connectionState == .reconnecting,
              let reconnectTarget,
              let candidate = ports.first(where: { reconnectTarget.representsSameDevice(as: $0) })
        else { return }

        configuration.path = candidate.path
        currentPortInfo = candidate
        attemptAutomaticReconnect()
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
            recordSendHistory()
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

    func applySendItem(text: String, format: SendFormat, lineEnding: LineEnding) {
        sendText = text
        sendFormat = format
        self.lineEnding = lineEnding
        sendError = nil
    }

    func clearSendHistory() {
        sendHistory.removeAll()
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
        reconnectPending = false
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
        let message = reason ?? "シリアルポートとの接続が終了しました。"
        recordSystemMessage(message)
        if autoReconnect, reconnectTarget != nil {
            reconnectPending = true
            connectionState = .reconnecting
            recordSystemMessage("デバイスの再接続を待機しています。")
        } else {
            connectionState = .failed(message)
        }
    }

    private func attemptAutomaticReconnect() {
        connectionState = .connecting
        do {
            try connection.open(configuration: configuration)
            reconnectPending = false
            reconnectTarget = currentPortInfo ?? SerialPortInfo(path: configuration.path)
            connectionState = .connected
            recordSystemMessage("\(configuration.path)へ自動再接続しました（\(configuration.shortDescription)）。")
        } catch {
            connectionState = .reconnecting
        }
    }

    private func recordSendHistory() {
        let item = SendHistoryEntry(
            text: sendText,
            format: sendFormat,
            lineEnding: lineEnding
        )
        if let first = sendHistory.first,
           first.text == item.text,
           first.format == item.format,
           first.lineEnding == item.lineEnding {
            return
        }
        sendHistory.insert(item, at: 0)
        if sendHistory.count > maximumSendHistoryEntries {
            sendHistory.removeLast(sendHistory.count - maximumSendHistoryEntries)
        }
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
