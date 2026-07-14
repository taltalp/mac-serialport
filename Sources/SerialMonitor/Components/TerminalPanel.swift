import AppKit
import SerialCore
import SwiftUI

struct TerminalPanel: View {
    @ObservedObject var session: SerialSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("通信ログ")
                    .font(.headline)
                Text("最大5,000イベント")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Toggle("自動スクロール", isOn: $session.autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button(action: session.clearEntries) {
                    Label("消去", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
            Divider()

            TerminalTextView(
                content: TerminalAttributedFormatter.make(
                    entries: session.entries,
                    mode: session.displayMode,
                    showTimestamps: session.showTimestamps,
                    showDirections: session.showDirections
                ),
                autoScroll: session.autoScroll
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            SendBar(session: session)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct SendBar: View {
    @ObservedObject var session: SerialSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField(
                    session.sendFormat == .ascii
                        ? "送信データを入力…"
                        : "16進数を入力（例: 7E 00 FF 0D 0A）",
                    text: $session.sendText
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(session.send)

                Picker("送信形式", selection: $session.sendFormat) {
                    ForEach(SendFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 105)

                Button("送信", action: session.send)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!session.isConnected || session.sendText.isEmpty)
            }

            HStack {
                if let error = session.sendError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if session.sendFormat == .ascii {
                    Text("Returnで送信 • 末尾に\(session.lineEnding.displayName)を付加")
                        .foregroundStyle(.secondary)
                } else {
                    Text("空白区切りの16進数で送信 • 改行コードは自動付加しません")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.caption)
            .lineLimit(1)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

@MainActor
private enum TerminalAttributedFormatter {
    static func make(
        entries: [SerialLogEntry],
        mode: DataDisplayMode,
        showTimestamps: Bool,
        showDirections: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let prefixAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        for entry in entries {
            if showTimestamps {
                result.append(NSAttributedString(
                    string: SerialDataFormatter.timestamp(entry.date) + "  ",
                    attributes: prefixAttributes
                ))
            }

            if showDirections {
                let directionColor: NSColor = switch entry.direction {
                case .received: .systemBlue
                case .transmitted: .systemOrange
                case .system: .secondaryLabelColor
                }
                result.append(NSAttributedString(
                    string: entry.direction.rawValue.padding(toLength: 3, withPad: " ", startingAt: 0) + "  ",
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold),
                        .foregroundColor: directionColor,
                        .paragraphStyle: paragraph
                    ]
                ))
            }

            let text: String
            if entry.direction == .system {
                text = SerialDataFormatter.asciiString(from: entry.data)
            } else {
                text = SerialDataFormatter.string(from: entry.data, mode: mode)
            }
            result.append(NSAttributedString(string: text, attributes: bodyAttributes))
            if !text.hasSuffix("\n") {
                result.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
            }
        }

        if entries.isEmpty {
            result.append(NSAttributedString(
                string: "ポートへ接続すると、ここに受信データが表示されます。",
                attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
            ))
        }
        return result
    }
}
