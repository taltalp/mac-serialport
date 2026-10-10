import AppKit
import SerialCore
import Testing
@testable import SerialMonitor

@Suite("受信ログの行表示")
@MainActor
struct TerminalAttributedFormatterTests {
    private let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let chip = "\u{FFFC}"

    @Test("一度に受信したCRLF区切りの各行と空行に時刻とRXを表示する", arguments: [false, true])
    func prefixesEveryCRLFLine(showChips: Bool) {
        var buffer = SerialLogBuffer()
        receive("first\r\nsecond\r\n\r\n", at: firstDate, into: &buffer)

        let rendered = render(buffer, showChips: showChips)
        let ending = showChips ? chip + chip + "\n" : "\n"
        #expect(rendered.string ==
            prefix(firstDate) + "first" + ending
            + prefix(firstDate) + "second" + ending
            + prefix(firstDate) + ending)
        #expect(attachmentCount(in: rendered) == (showChips ? 6 : 0))
    }

    @Test("分割受信した行には先頭の受信時刻だけを表示しCRとLFの間でも行を増やさない", arguments: [false, true])
    func keepsOnePrefixAcrossReads(showChips: Bool) {
        let secondDate = firstDate.addingTimeInterval(1)
        let thirdDate = firstDate.addingTimeInterval(2)
        let fourthDate = firstDate.addingTimeInterval(3)
        var buffer = SerialLogBuffer()

        receive("waiting for re", at: firstDate, into: &buffer)
        #expect(render(buffer, showChips: showChips).string ==
            prefix(firstDate) + "waiting for re\n")

        receive("sponse\r", at: secondDate, into: &buffer)
        let crEnding = showChips ? chip + "\n" : "\n"
        #expect(render(buffer, showChips: showChips).string ==
            prefix(firstDate) + "waiting for response" + crEnding)

        receive("\nnext", at: thirdDate, into: &buffer)
        let crlfEnding = showChips ? chip + chip + "\n" : "\n"
        #expect(render(buffer, showChips: showChips).string ==
            prefix(firstDate) + "waiting for response" + crlfEnding
            + prefix(thirdDate) + "next\n")

        receive(" line\r\n", at: fourthDate, into: &buffer)
        #expect(render(buffer, showChips: showChips).string ==
            prefix(firstDate) + "waiting for response" + crlfEnding
            + prefix(thirdDate) + "next line" + crlfEnding)
    }

    @Test("CR単体の改行は制御コードチップの表示設定に関わらず一行ずつ表示する", arguments: [false, true])
    func rendersStandaloneCRLines(showChips: Bool) {
        var buffer = SerialLogBuffer()
        receive("first\rsecond\r", at: firstDate, into: &buffer)

        let rendered = render(buffer, showChips: showChips)
        let ending = showChips ? chip + "\n" : "\n"
        #expect(rendered.string ==
            prefix(firstDate) + "first" + ending
            + prefix(firstDate) + "second" + ending)
        #expect(attachmentCount(in: rendered) == (showChips ? 2 : 0))
    }

    @Test("ASCIIとHEXは同じ受信行と時刻を表示する", arguments: [false, true])
    func alignsASCIILinesWithHex(showChips: Bool) {
        let secondDate = firstDate.addingTimeInterval(1)
        var buffer = SerialLogBuffer()
        receive("A\r\nB", at: firstDate, into: &buffer)
        receive("C\r\nD\n", at: secondDate, into: &buffer)

        let ascii = render(buffer, showChips: showChips)
        let hex = render(buffer, mode: .hex, showChips: showChips)
        let crlfEnding = showChips ? chip + chip + "\n" : "\n"
        let lfEnding = showChips ? chip + "\n" : "\n"
        #expect(ascii.string ==
            prefix(firstDate) + "A" + crlfEnding
            + prefix(firstDate) + "BC" + crlfEnding
            + prefix(secondDate) + "D" + lfEnding)
        #expect(hex.string ==
            prefix(firstDate) + "41 0D 0A\n"
            + prefix(firstDate) + "42 43 0D 0A\n"
            + prefix(secondDate) + "44 0A\n")
        #expect(attachmentCount(in: hex) == 0)
    }

    private func receive(_ text: String, at date: Date, into buffer: inout SerialLogBuffer) {
        buffer.append(SerialLogEntry(date: date, direction: .received, data: Data(text.utf8)))
    }

    @Test("長い行の先頭を省略した場合はASCIIとHEXで明示する", arguments: [DataDisplayMode.ascii, .hex])
    func marksTruncatedLines(mode: DataDisplayMode) {
        var buffer = SerialLogBuffer(maximumBytes: 4)
        receive("abcdef", at: firstDate, into: &buffer)

        let body = mode == .ascii ? "cdef" : "63 64 65 66"
        #expect(render(buffer, mode: mode, showChips: false).string ==
            prefix(firstDate) + "…（先頭を省略） " + body + "\n")
    }

    private func prefix(_ date: Date) -> String {
        SerialDataFormatter.timestamp(date) + "  RX   "
    }

    private func render(
        _ buffer: SerialLogBuffer,
        mode: DataDisplayMode = .ascii,
        showChips: Bool
    ) -> NSAttributedString {
        TerminalAttributedFormatter.make(
            entries: buffer.entries,
            mode: mode,
            showTimestamps: true,
            showDirections: true,
            showControlCodeChips: showChips,
            searchQuery: "",
            emptyMessage: "ログなし"
        )
    }

    private func attachmentCount(in text: NSAttributedString) -> Int {
        (0..<text.length).filter {
            text.attribute(.attachment, at: $0, effectiveRange: nil) is NSTextAttachment
        }.count
    }
}
