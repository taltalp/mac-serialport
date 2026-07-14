import SerialCore
import SwiftUI

struct ConnectionBar: View {
    @ObservedObject var session: SerialSession
    let availablePorts: [SerialPortInfo]
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ポート")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("ポート", selection: $session.configuration.path) {
                        if session.configuration.path.isEmpty {
                            Text("ポートを選択").tag("")
                        }
                        ForEach(portChoices) { port in
                            Text(port.menuTitle).tag(port.path)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 310)
                }

                SettingPicker(title: "ボーレート", width: 120) {
                    Picker("ボーレート", selection: $session.configuration.baudRate) {
                        ForEach(SerialConfiguration.supportedBaudRates, id: \.self) {
                            Text($0.formatted(.number.grouping(.never))).tag($0)
                        }
                    }
                }

                SettingPicker(title: "データ", width: 75) {
                    Picker("データビット", selection: $session.configuration.dataBits) {
                        ForEach(5...8, id: \.self) { Text("\($0)").tag($0) }
                    }
                }

                SettingPicker(title: "パリティ", width: 90) {
                    Picker("パリティ", selection: $session.configuration.parity) {
                        ForEach(SerialParity.allCases) { parity in
                            Text(parity.displayName).tag(parity)
                        }
                    }
                }

                SettingPicker(title: "ストップ", width: 75) {
                    Picker("ストップビット", selection: $session.configuration.stopBits) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                    }
                }
            }
            .disabled(session.isConnected || session.connectionState == .connecting)

            Spacer(minLength: 8)

            Button(action: session.toggleConnection) {
                Text(session.isConnected ? "切断" : "接続")
                    .frame(minWidth: 78)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.isConnected ? .red : .accentColor)
            .controlSize(.large)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("ポート一覧を更新")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if session.isConnected {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
    }

    private var portChoices: [SerialPortInfo] {
        if session.configuration.path.isEmpty
            || availablePorts.contains(where: { $0.path == session.configuration.path }) {
            return availablePorts
        }
        return [session.currentPortInfo ?? SerialPortInfo(path: session.configuration.path)]
            + availablePorts
    }
}

private struct SettingPicker<Content: View>: View {
    let title: String
    let width: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .labelsHidden()
                .frame(width: width)
        }
    }
}
