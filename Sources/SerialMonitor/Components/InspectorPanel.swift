import AppKit
import SerialCore
import SwiftUI

struct InspectorPanel: View {
    @ObservedObject var session: SerialSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("表示・通信設定")
                    .font(.title3.bold())

                GroupBox("接続・USBデバイス") {
                    VStack(alignment: .leading, spacing: 11) {
                        Toggle("自動再接続", isOn: $session.autoReconnect)
                            .help("同じUSB機器が再び接続されたときに自動でポートを開きます")

                        Divider()

                        if let info = session.currentPortInfo {
                            deviceInfo(info)
                        } else {
                            Text("ポートを選択するとデバイス情報を表示します")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }

                GroupBox("表示") {
                    VStack(alignment: .leading, spacing: 13) {
                        Picker("表示形式", selection: $session.displayMode) {
                            ForEach(DataDisplayMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("受信日時", isOn: $session.showTimestamps)
                        Toggle("送受信方向", isOn: $session.showDirections)
                        Toggle("制御コードを表示", isOn: $session.showControlCodeChips)
                            .disabled(session.displayMode == .hex)
                            .help("CR・LF・TAB・NULなどをASCII表示内で可視化します")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }

                GroupBox("送信") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("改行コード") {
                            Picker("改行コード", selection: $session.lineEnding) {
                                ForEach(LineEnding.allCases) { ending in
                                    Text(ending.displayName).tag(ending)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }

                        LabeledContent("フロー制御") {
                            Picker("フロー制御", selection: $session.configuration.flowControl) {
                                ForEach(SerialFlowControl.allCases) { control in
                                    Text(control.displayName).tag(control)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                        .disabled(session.isConnected)
                    }
                    .padding(.top, 4)
                }

                GroupBox("リアルタイムログ") {
                    VStack(alignment: .leading, spacing: 11) {
                        Toggle("ログへ保存", isOn: loggingBinding)

                        if let url = session.loggingURL {
                            Text(url.lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(url.path)
                            Button("保存先を変更…", action: chooseLogFile)
                        } else {
                            Text("保存先が選択されていません")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }

                GroupBox("通信量") {
                    HStack {
                        CounterBadge(label: "RX", color: .blue, bytes: session.receivedBytes)
                        Spacer()
                        CounterBadge(label: "TX", color: .orange, bytes: session.transmittedBytes)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var loggingBinding: Binding<Bool> {
        Binding(
            get: { session.isLogging },
            set: { enabled in
                if enabled {
                    chooseLogFile()
                } else {
                    session.stopLogging()
                }
            }
        )
    }

    @ViewBuilder
    private func deviceInfo(_ info: SerialPortInfo) -> some View {
        LabeledContent("デバイス") {
            Text(info.deviceName)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(info.deviceName)
        }
        if let manufacturer = info.manufacturer {
            LabeledContent("メーカー") {
                Text(manufacturer)
                    .lineLimit(1)
                    .help(manufacturer)
            }
        }
        if let vendorProductText = info.vendorProductText {
            LabeledContent("VID:PID", value: vendorProductText)
        }
        if let serialNumber = info.serialNumber {
            LabeledContent("シリアル") {
                Text(serialNumber)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(serialNumber)
            }
        }
        if let locationID = info.locationID {
            LabeledContent("接続位置", value: String(format: "0x%08X", locationID))
        }
        LabeledContent("ポート") {
            Text(info.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(info.path)
        }
        .font(.callout)
        .textSelection(.enabled)
    }

    private func chooseLogFile() {
        let panel = NSSavePanel()
        panel.title = "リアルタイムログの保存先"
        panel.nameFieldStringValue = defaultLogFileName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            session.startLogging(to: url)
        }
    }

    private var defaultLogFileName: String {
        if let url = session.loggingURL {
            return url.lastPathComponent
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "serial-\(formatter.string(from: Date())).log"
    }
}

private struct CounterBadge: View {
    let label: String
    let color: Color
    let bytes: Int

    var body: some View {
        HStack(spacing: 7) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(color, in: RoundedRectangle(cornerRadius: 4))
            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                .monospacedDigit()
        }
    }
}
