import AppKit
import SerialCore
import SwiftUI

struct TerminalPanel: View {
    @ObservedObject var session: SerialSession
    @ObservedObject var commandStore: SendCommandStore

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

            searchBar
            Divider()

            logView

            Divider()
            SendBar(session: session, commandStore: commandStore)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("ASCII / HEXを検索", text: $session.logSearchText)
                    .textFieldStyle(.plain)
                if !session.logSearchText.isEmpty {
                    Button {
                        session.logSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("検索を消去")
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: 330)
            .frame(height: 26)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }

            Picker("方向", selection: $session.logDirectionFilter) {
                ForEach(LogDirectionFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)

            Toggle("一致のみ", isOn: $session.showOnlySearchMatches)
                .toggleStyle(.checkbox)
                .disabled(trimmedSearchText.isEmpty)

            Spacer()

            if !trimmedSearchText.isEmpty {
                Text("\(matchingEntryCount)件一致")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if session.logDirectionFilter != .all {
                Text("\(directionFilteredEntries.count)件")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Color(nsColor: .windowBackgroundColor))
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
            entries: visibleEntries,
            mode: mode,
            showTimestamps: session.showTimestamps,
            showDirections: session.showDirections,
            showControlCodeChips: session.showControlCodeChips,
            searchQuery: trimmedSearchText,
            emptyMessage: session.entries.isEmpty
                ? "ポートへ接続すると、ここに受信データが表示されます。"
                : "条件に一致する通信ログはありません。"
        )
    }

    private var trimmedSearchText: String {
        session.logSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var directionFilteredEntries: [SerialLogEntry] {
        session.entries.filter { session.logDirectionFilter.includes($0.direction) }
    }

    private var matchingEntries: [SerialLogEntry] {
        guard !trimmedSearchText.isEmpty else { return directionFilteredEntries }
        return directionFilteredEntries.filter {
            SerialDataFormatter.matchesSearch(data: $0.data, query: trimmedSearchText)
        }
    }

    private var visibleEntries: [SerialLogEntry] {
        if session.showOnlySearchMatches, !trimmedSearchText.isEmpty {
            return matchingEntries
        }
        return directionFilteredEntries
    }

    private var matchingEntryCount: Int {
        matchingEntries.count
    }
}

private struct SendBar: View {
    @ObservedObject var session: SerialSession
    @ObservedObject var commandStore: SendCommandStore
    @State private var isShowingPresetAlert = false
    @State private var presetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                historyMenu
                presetMenu

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
        .alert("定型コマンドを登録", isPresented: $isShowingPresetAlert) {
            TextField("名前", text: $presetName)
            Button("キャンセル", role: .cancel) {}
            Button("登録") {
                commandStore.add(
                    name: presetName,
                    text: session.sendText,
                    format: session.sendFormat,
                    lineEnding: session.lineEnding
                )
            }
            .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("現在の入力内容・送信形式・改行コードを保存します。")
        }
    }

    private var historyMenu: some View {
        Menu {
            if session.sendHistory.isEmpty {
                Text("送信履歴はありません")
            } else {
                ForEach(session.sendHistory) { item in
                    Button(historyTitle(item)) {
                        session.applySendItem(
                            text: item.text,
                            format: item.format,
                            lineEnding: item.lineEnding
                        )
                    }
                }
                Divider()
                Button("履歴を消去", role: .destructive, action: session.clearSendHistory)
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("送信履歴")
    }

    private var presetMenu: some View {
        Menu {
            if commandStore.presets.isEmpty {
                Text("定型コマンドはありません")
            } else {
                ForEach(commandStore.presets) { preset in
                    Button(preset.name) {
                        session.applySendItem(
                            text: preset.text,
                            format: preset.format,
                            lineEnding: preset.lineEnding
                        )
                    }
                }
                Divider()
            }

            Button("現在の入力を登録…") {
                presetName = suggestedPresetName
                isShowingPresetAlert = true
            }
            .disabled(session.sendText.isEmpty)

            if !commandStore.presets.isEmpty {
                Menu("定型コマンドを削除") {
                    ForEach(commandStore.presets) { preset in
                        Button(preset.name, role: .destructive) {
                            commandStore.remove(preset)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "star")
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("定型コマンド")
    }

    private func historyTitle(_ item: SendHistoryEntry) -> String {
        let oneLine = item.text
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        let body = oneLine.count > 42 ? String(oneLine.prefix(42)) + "…" : oneLine
        let ending = item.format == .ascii && item.lineEnding != .none
            ? " + \(item.lineEnding.displayName)"
            : ""
        return "[\(item.format.displayName)] \(body)\(ending)"
    }

    private var suggestedPresetName: String {
        let oneLine = session.sendText
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > 24 ? String(oneLine.prefix(24)) + "…" : oneLine
    }
}

@MainActor
private enum TerminalAttributedFormatter {
    static func make(
        entries: [SerialLogEntry],
        mode: DataDisplayMode,
        showTimestamps: Bool,
        showDirections: Bool,
        showControlCodeChips: Bool,
        searchQuery: String,
        emptyMessage: String
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

            let bodyStart = result.length
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
            highlightSearch(
                in: result,
                range: NSRange(location: bodyStart, length: result.length - bodyStart),
                query: searchQuery,
                mode: mode
            )
        }

        if entries.isEmpty {
            result.append(NSAttributedString(
                string: emptyMessage,
                attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
            ))
        }
        return result
    }

    private static func highlightSearch(
        in result: NSMutableAttributedString,
        range: NSRange,
        query: String,
        mode: DataDisplayMode
    ) {
        guard !query.isEmpty, range.length > 0 else { return }

        var queries = [query]
        if mode == .hex, let compact = SerialDataFormatter.normalizedHexSearchQuery(query) {
            queries.append(stride(from: 0, to: compact.count, by: 2).map { index in
                    let start = compact.index(compact.startIndex, offsetBy: index)
                    let end = compact.index(start, offsetBy: 2)
                    return String(compact[start..<end])
            }.joined(separator: " "))
        }

        let text = result.string as NSString
        var highlightedRanges = Set<String>()
        for candidate in queries where !candidate.isEmpty {
            var remainingRange = range
            while remainingRange.length > 0 {
                let found = text.range(
                    of: candidate,
                    options: .caseInsensitive,
                    range: remainingRange
                )
                guard found.location != NSNotFound else { break }
                let key = "\(found.location):\(found.length)"
                if highlightedRanges.insert(key).inserted {
                    result.addAttributes([
                        .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.42),
                        .foregroundColor: NSColor.labelColor
                    ], range: found)
                }
                let nextLocation = found.location + max(found.length, 1)
                let rangeEnd = range.location + range.length
                remainingRange = NSRange(
                    location: nextLocation,
                    length: max(0, rangeEnd - nextLocation)
                )
            }
        }
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
