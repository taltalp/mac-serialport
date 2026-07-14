import SerialCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if let session = model.selectedSession {
                VStack(spacing: 0) {
                    ConnectionBar(
                        session: session,
                        availablePorts: model.availablePorts,
                        onRefresh: model.refreshPorts
                    )
                    Divider()
                    SessionTabBar(model: model)
                    Divider()
                    HStack(spacing: 0) {
                        TerminalPanel(session: session)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        InspectorPanel(session: session)
                            .frame(width: 315)
                    }
                    Divider()
                    StatusBar(session: session)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("接続タブがありません")
                        .font(.title2.bold())
                    Text("新しい接続タブを追加してください。")
                        .foregroundStyle(.secondary)
                    Button("接続タブを追加", action: model.addSession)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                model.refreshPorts()
            }
        }
    }
}

private struct SessionTabBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.sessions) { session in
                        SessionTab(
                            session: session,
                            isSelected: model.selectedSessionID == session.id,
                            canClose: model.sessions.count > 1,
                            onSelect: { model.selectedSessionID = session.id },
                            onClose: { model.closeSession(session.id) }
                        )
                    }
                }
            }

            Spacer(minLength: 0)
            Button(action: model.addSession) {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("新しい接続タブ")
            .padding(.horizontal, 10)
        }
        .frame(height: 43)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SessionTab: View {
    @ObservedObject var session: SerialSession
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(session.title)
                    .lineLimit(1)
                if canClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("タブを閉じる")
                }
            }
            .padding(.horizontal, 16)
            .frame(minWidth: 190, minHeight: 42)
            .background(isSelected ? Color(nsColor: .controlBackgroundColor) : .clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? Color.accentColor : .clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private var statusColor: Color {
        switch session.connectionState {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        case .disconnected: .secondary
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var session: SerialSession

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
            Text(session.statusText)
                .lineLimit(1)

            if !session.configuration.path.isEmpty {
                Text(session.configuration.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(session.configuration.shortDescription)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if session.isLogging {
                Label("ログ保存中", systemImage: "doc.text")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusColor: Color {
        switch session.connectionState {
        case .connected: .green
        case .connecting: .orange
        case .failed: .red
        case .disconnected: .secondary
        }
    }
}
