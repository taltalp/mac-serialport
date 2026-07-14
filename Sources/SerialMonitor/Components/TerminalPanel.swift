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

            logView

            Divider()
            SendBar(session: session)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var logView: some View {
        if session.displayMode == .asciiAndHex {
            HSplitView {
                splitLogPane(title: "ASCII", mode: .ascii)
                splitLogPane(title: "HEX", mode: .hex)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TerminalTextView(
                content: formattedLog(mode: session.displayMode),
                autoScroll: session.autoScroll
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func splitLogPane(title: String, mode: DataDisplayMode) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            TerminalTextView(
                content: formattedLog(mode: mode),
                autoScroll: session.autoScroll
            )
        }
        .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formattedLog(mode: DataDisplayMode) -> NSAttributedString {
        TerminalAttributedFormatter.make(
            entries: session.entries,
            mode: mode,
            showTimestamps: session.showTimestamps,
            showDirections: session.showDirections,
            showControlCodeChips: session.showControlCodeChips
        )
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
        showDirections: Bool,
        showControlCodeChips: Bool
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

            if showControlCodeChips, mode == .ascii {
                let endsWithLineBreak = appendASCIIWithControlCodeChips(
                    entry.data,
                    to: result,
                    attributes: bodyAttributes
                )
                if !endsWithLineBreak {
                    result.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
                }
            } else {
                let text: String
                if entry.direction == .system {
                    text = SerialDataFormatter.asciiDisplayString(from: entry.data)
                } else {
                    text = SerialDataFormatter.string(from: entry.data, mode: mode)
                }
                result.append(NSAttributedString(string: text, attributes: bodyAttributes))
                if !text.hasSuffix("\n") {
                    result.append(NSAttributedString(string: "\n", attributes: bodyAttributes))
                }
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

    private static func appendASCIIWithControlCodeChips(
        _ data: Data,
        to result: NSMutableAttributedString,
        attributes: [NSAttributedString.Key: Any]
    ) -> Bool {
        var plainText = ""

        func flushPlainText() {
            guard !plainText.isEmpty else { return }
            result.append(NSAttributedString(string: plainText, attributes: attributes))
            plainText.removeAll(keepingCapacity: true)
        }

        for byte in data {
            if let label = SerialDataFormatter.controlCodeLabel(for: byte) {
                flushPlainText()
                result.append(ControlCodeChipRenderer.attributedString(for: label))
                if byte == 0x0A {
                    result.append(NSAttributedString(string: "\n", attributes: attributes))
                }
            } else if (0x20...0x7E).contains(byte) {
                plainText.append(Character(UnicodeScalar(byte)))
            } else {
                plainText.append("·")
            }
        }

        flushPlainText()
        return data.last == 0x0A
    }
}

@MainActor
private enum ControlCodeChipRenderer {
    private static var attachmentCache: [String: NSTextAttachment] = [:]

    static func attributedString(for label: String) -> NSAttributedString {
        if let attachment = attachmentCache[label] {
            return NSAttributedString(attachment: attachment)
        }

        let font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = (label as NSString).size(withAttributes: textAttributes)
        let imageSize = NSSize(width: ceil(textSize.width) + 12, height: 17)
        let image = NSImage(size: imageSize, flipped: true) { bounds in
            let chipRect = bounds.insetBy(dx: 1, dy: 1.5)
            let chipPath = NSBezierPath(roundedRect: chipRect, xRadius: 4.5, yRadius: 4.5)
            NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
            chipPath.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.42).setStroke()
            chipPath.lineWidth = 0.8
            chipPath.stroke()

            let textOrigin = NSPoint(
                x: floor((bounds.width - textSize.width) / 2),
                y: floor((bounds.height - textSize.height) / 2)
            )
            (label as NSString).draw(at: textOrigin, withAttributes: textAttributes)
            return true
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(origin: NSPoint(x: 0, y: -3), size: imageSize)
        attachment.lineLayoutPadding = 1
        attachment.allowsTextAttachmentView = false
        attachmentCache[label] = attachment
        return NSAttributedString(attachment: attachment)
    }
}
