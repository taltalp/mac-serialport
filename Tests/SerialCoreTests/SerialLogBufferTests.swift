import Foundation
import Testing
@testable import SerialCore

@Suite("受信ログの行分割")
struct SerialLogBufferTests {
    private let firstDate = Date(timeIntervalSince1970: 1_000)
    private let secondDate = Date(timeIntervalSince1970: 2_000)

    @Test("1回の受信に含まれる各行へ受信時刻を付ける")
    func splitMultipleLines() {
        var buffer = SerialLogBuffer()
        buffer.append(received("first\r\nsecond\rthird\nfourth", at: firstDate))

        #expect(buffer.entries.map(\.data) == dataLines([
            "first\r\n", "second\r", "third\n", "fourth"
        ]))
        #expect(buffer.entries.allSatisfy { $0.date == firstDate })
        #expect(buffer.entries.allSatisfy { $0.direction == .received })
        #expect(Set(buffer.entries.map(\.id)).count == 4)
    }

    @Test("未完行は即時表示し次の受信を同じIDと先頭時刻で追記する")
    func appendToIncompleteLine() throws {
        var buffer = SerialLogBuffer()
        buffer.append(received("res", at: firstDate))
        let initialEntry = try #require(buffer.entries.first)
        #expect(initialEntry.data == Data("res".utf8))

        buffer.append(received("ponse\r\nnext", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["response\r\n", "next"]))
        let completedEntry = try #require(buffer.entries.first)
        #expect(completedEntry.id == initialEntry.id)
        #expect(completedEntry.date == firstDate)
        #expect(buffer.entries.last?.date == secondDate)
    }

    @Test("別々に受信したCRとLFは同じ行の改行コードになる")
    func splitCRLF() throws {
        var buffer = SerialLogBuffer()
        buffer.append(received("OK\r", at: firstDate))
        let initialID = try #require(buffer.entries.first?.id)

        buffer.append(received("\nnext\r\n", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["OK\r\n", "next\r\n"]))
        #expect(buffer.entries.first?.id == initialID)
        #expect(buffer.entries.map(\.date) == [firstDate, secondDate])
    }

    @Test("連続する改行の空行を保持し末尾に余分な行を作らない")
    func preserveEmptyLines() {
        var buffer = SerialLogBuffer()
        buffer.append(received("\r\n\r\n\n\r\r\n", at: firstDate))

        #expect(buffer.entries.map(\.data) == dataLines(["\r\n", "\r\n", "\n", "\r", "\r\n"]))
        #expect(buffer.entries.allSatisfy { $0.date == firstDate })
    }

    @Test("改行コードを含むストリームの全受信分割で行と先頭時刻を保持する")
    func everyChunkPartition() {
        let bytes = Array("A\r\n\rB\n\nC\rD".utf8)
        let expectedLines = dataLines(["A\r\n", "\r", "B\n", "\n", "C\r", "D"])
        let lineStartOffsets = [0, 3, 4, 6, 7, 9]

        for boundaries in 0..<(1 << (bytes.count - 1)) {
            var buffer = SerialLogBuffer()
            var datesByByte: [Date] = []
            var start = 0
            var chunkIndex = 0

            for end in 1...bytes.count {
                guard end == bytes.count || boundaries & (1 << (end - 1)) != 0 else {
                    continue
                }
                let date = firstDate.addingTimeInterval(Double(chunkIndex))
                buffer.append(SerialLogEntry(
                    date: date,
                    direction: .received,
                    data: Data(bytes[start..<end])
                ))
                datesByByte.append(contentsOf: repeatElement(date, count: end - start))
                start = end
                chunkIndex += 1
            }

            #expect(buffer.entries.map(\.data) == expectedLines)
            #expect(buffer.entries.map(\.date) == lineStartOffsets.map { datesByByte[$0] })
            #expect(Set(buffer.entries.map(\.id)).count == expectedLines.count)
            #expect(buffer.entries.flatMap { Array($0.data) } == bytes)
        }
    }

    @Test("空の受信では行を増やさずCRLFの継続状態も変えない")
    func ignoreEmptyReceive() {
        var buffer = SerialLogBuffer()
        buffer.append(received("", at: firstDate))
        #expect(buffer.entries.isEmpty)

        buffer.append(received("OK\r", at: firstDate))
        buffer.append(received("", at: secondDate))
        buffer.append(received("\n", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["OK\r\n"]))
        #expect(buffer.entries.first?.date == firstDate)
    }

    @Test("TXとSYSはイベント単位で保持し介入後も先頭受信順のRX行へ追記する")
    func interleavedEvents() throws {
        var buffer = SerialLogBuffer()
        buffer.append(received("par", at: firstDate))
        let initialID = try #require(buffer.entries.first?.id)
        let transmitted = SerialLogEntry(
            date: secondDate,
            direction: .transmitted,
            data: Data("command\r\nsecond command\r\n".utf8)
        )
        let system = SerialLogEntry(
            date: secondDate,
            direction: .system,
            data: Data("status\nready".utf8)
        )
        buffer.append(transmitted)
        buffer.append(system)
        buffer.append(received("tial\nnext", at: secondDate))

        #expect(buffer.entries.map(\.data) == [
            Data("partial\n".utf8), transmitted.data, system.data, Data("next".utf8)
        ])
        #expect(buffer.entries.map(\.direction) == [.received, .transmitted, .system, .received])
        #expect(Array(buffer.entries.prefix(3)).map(\.id) == [initialID, transmitted.id, system.id])
        #expect(buffer.entries.first?.date == firstDate)
        #expect(buffer.entries.last?.date == secondDate)
    }

    @Test("TXの介入を挟んでCRLFを受信しても1行のまま保持する")
    func interleavedSplitCRLF() {
        var buffer = SerialLogBuffer()
        buffer.append(received("OK\r", at: firstDate))
        buffer.append(SerialLogEntry(direction: .transmitted, data: Data("AT\r\n".utf8)))
        buffer.append(received("\nnext", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["OK\r\n", "AT\r\n", "next"]))
        #expect(buffer.entries.first?.date == firstDate)
        #expect(buffer.entries.last?.date == secondDate)
    }

    @Test("受信終了では表示済み行を保持し次の受信との連結を解除する", arguments: ["partial", "OK\r"])
    func finishReceivingPreservesEntries(previousText: String) throws {
        var buffer = SerialLogBuffer()
        buffer.append(received(previousText, at: firstDate))
        let initialID = try #require(buffer.entries.first?.id)

        buffer.finishReceiving()
        #expect(buffer.entries.map(\.data) == dataLines([previousText]))
        buffer.append(received("\nnext", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines([previousText, "\n", "next"]))
        #expect(buffer.entries.first?.id == initialID)
        #expect(buffer.entries.map(\.date) == [firstDate, secondDate, secondDate])
    }

    @Test("クリアは行と受信の連結状態を両方消去する", arguments: ["partial", "OK\r"])
    func removeAllResetsReceiving(previousText: String) {
        var buffer = SerialLogBuffer()
        buffer.append(received(previousText, at: firstDate))

        buffer.removeAll()
        #expect(buffer.entries.isEmpty)
        buffer.append(received("\nnext", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["\n", "next"]))
        #expect(buffer.entries.allSatisfy { $0.date == secondDate })
    }

    @Test("行数上限を超えたら古い行を削除して未完行への追記を継続する")
    func trimOldLines() throws {
        var buffer = SerialLogBuffer(maximumEntries: 2)
        buffer.append(received("old\nsecond\nthi", at: firstDate))
        #expect(buffer.entries.map(\.data) == dataLines(["second\n", "thi"]))
        let partialID = try #require(buffer.entries.last?.id)

        buffer.append(received("rd\nfourth\n", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["third\n", "fourth\n"]))
        #expect(buffer.entries.first?.id == partialID)
        #expect(buffer.entries.map(\.date) == [firstDate, secondDate])
    }

    @Test("古い行の削除でRX行の位置が変わっても正しい行へ追記する")
    func adjustReceivePositionAfterTrimming() throws {
        var buffer = SerialLogBuffer(maximumEntries: 3)
        buffer.append(received("old\npar", at: firstDate))
        let partialID = try #require(buffer.entries.last?.id)
        buffer.append(SerialLogEntry(direction: .transmitted, data: Data("command".utf8)))
        buffer.append(SerialLogEntry(direction: .system, data: Data("status".utf8)))
        buffer.append(received("tial\n", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["partial\n", "command", "status"]))
        #expect(buffer.entries.first?.id == partialID)
        #expect(buffer.entries.first?.date == firstDate)
        #expect(buffer.entries.map(\.direction) == [.received, .transmitted, .system])
    }

    @Test("未完RX行自体が削除された後も次の受信を別のイベントへ混ぜない")
    func handleEvictedIncompleteLine() {
        var buffer = SerialLogBuffer(maximumEntries: 2)
        buffer.append(received("evicted", at: firstDate))
        buffer.append(SerialLogEntry(direction: .transmitted, data: Data("command".utf8)))
        buffer.append(SerialLogEntry(direction: .system, data: Data("status".utf8)))
        buffer.append(received("next\n", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["status", "next\n"]))
        #expect(buffer.entries.map(\.direction) == [.system, .received])
        #expect(buffer.entries.last?.date == secondDate)
    }

    @Test("バイナリを含む受信の元バイトを保ち受信境界をまたいで検索できる")
    func preserveRawBytesAndSearch() throws {
        var buffer = SerialLogBuffer()
        let chunks: [[UInt8]] = [[0x00, 0xFF, 0x41], [0x42, 0x0D], [0x0A, 0x43]]
        for (index, bytes) in chunks.enumerated() {
            buffer.append(SerialLogEntry(
                date: firstDate.addingTimeInterval(Double(index)),
                direction: .received,
                data: Data(bytes)
            ))
        }

        let first = try #require(buffer.entries.first)
        #expect(buffer.entries.map(\.data) == [Data([0x00, 0xFF, 0x41, 0x42, 0x0D, 0x0A]), Data([0x43])])
        #expect(buffer.entries.flatMap { Array($0.data) } == chunks.flatMap { $0 })
        #expect(SerialDataFormatter.matchesSearch(data: first.data, query: "AB"))
        #expect(SerialDataFormatter.matchesSearch(data: first.data, query: "FF 41 42"))
        #expect(SerialDataFormatter.hexString(from: first.data) == "00 FF 41 42 0D 0A")
    }

    @Test("バイト上限を超えたら古い行から削除し残る完全な行は省略扱いにしない")
    func trimOldLinesForByteLimit() {
        var buffer = SerialLogBuffer(maximumBytes: 8)
        buffer.append(received("old\nnew\n", at: firstDate))
        #expect(buffer.entries.map(\.data) == dataLines(["old\n", "new\n"]))

        buffer.append(received("end\n", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["new\n", "end\n"]))
        #expect(buffer.entries.map(\.date) == [firstDate, secondDate])
        #expect(buffer.entries.allSatisfy { !$0.isTruncated })
        #expect(buffer.entries.reduce(0) { $0 + $1.data.count } == 8)
    }

    @Test("改行のない長い行は先頭を省略しIDと受信時刻を保って追記する")
    func truncateLongIncompleteLine() throws {
        var buffer = SerialLogBuffer(maximumBytes: 6)
        buffer.append(received("0123", at: firstDate))
        let initialID = try #require(buffer.entries.first?.id)
        #expect(buffer.entries.first?.isTruncated == false)

        buffer.append(received("456789", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["456789"]))
        #expect(buffer.entries.first?.isTruncated == true)
        #expect(buffer.entries.first?.id == initialID)
        #expect(buffer.entries.first?.date == firstDate)

        buffer.append(received("ABC\r", at: secondDate))
        #expect(buffer.entries.map(\.data) == dataLines(["89ABC\r"]))
        buffer.append(received("\n", at: secondDate))
        #expect(buffer.entries.map(\.data) == dataLines(["9ABC\r\n"]))
        #expect(buffer.entries.first?.id == initialID)
        #expect(buffer.entries.first?.date == firstDate)
        #expect(buffer.entries.first?.isTruncated == true)

        buffer.append(received("D\n", at: secondDate))
        #expect(buffer.entries.map(\.data) == dataLines(["D\n"]))
        #expect(buffer.entries.first?.date == secondDate)
        #expect(buffer.entries.first?.isTruncated == false)
    }

    @Test("CRLFより小さいバイト上限でもCRとLFを同じ行へ追記する")
    func truncateSplitCRLFWithOneByteLimit() throws {
        var buffer = SerialLogBuffer(maximumBytes: 1)
        buffer.append(received("A\r", at: firstDate))
        let initialID = try #require(buffer.entries.first?.id)
        #expect(buffer.entries.map(\.data) == dataLines(["\r"]))

        buffer.append(received("\n", at: secondDate))
        #expect(buffer.entries.map(\.data) == dataLines(["\n"]))
        #expect(buffer.entries.first?.id == initialID)
        #expect(buffer.entries.first?.date == firstDate)
        #expect(buffer.entries.first?.isTruncated == true)

        buffer.append(received("B", at: secondDate))
        #expect(buffer.entries.map(\.data) == dataLines(["B"]))
        #expect(buffer.entries.first?.date == secondDate)
        #expect(buffer.entries.first?.isTruncated == false)
    }

    @Test("バイト上限で古い行が削除されても途中のRX行へ正しく追記する")
    func adjustReceivePositionAfterByteTrimming() throws {
        var buffer = SerialLogBuffer(maximumBytes: 10)
        buffer.append(received("old\npar", at: firstDate))
        let partialID = try #require(buffer.entries.last?.id)
        buffer.append(SerialLogEntry(direction: .transmitted, data: Data("cmd".utf8)))
        buffer.append(SerialLogEntry(direction: .system, data: Data("st".utf8)))
        buffer.append(received("t\n", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["part\n", "cmd", "st"]))
        #expect(buffer.entries.first?.id == partialID)
        #expect(buffer.entries.first?.date == firstDate)
        #expect(buffer.entries.allSatisfy { !$0.isTruncated })
        #expect(buffer.entries.reduce(0) { $0 + $1.data.count } == 10)
    }

    @Test("バイト上限で未完RX行が削除された後の受信を他イベントへ混ぜない")
    func handleIncompleteLineEvictedByByteLimit() {
        var buffer = SerialLogBuffer(maximumBytes: 6)
        buffer.append(received("part", at: firstDate))
        buffer.append(SerialLogEntry(direction: .transmitted, data: Data("cmd".utf8)))
        buffer.append(received("X\n", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["cmd", "X\n"]))
        #expect(buffer.entries.map(\.direction) == [.transmitted, .received])
        #expect(buffer.entries.last?.date == secondDate)
        #expect(buffer.entries.allSatisfy { !$0.isTruncated })
    }

    @Test("クリアは保持バイト数と省略状態もリセットする")
    func removeAllResetsByteLimitState() {
        var buffer = SerialLogBuffer(maximumBytes: 4)
        buffer.append(received("0123456789", at: firstDate))
        #expect(buffer.entries.first?.isTruncated == true)

        buffer.removeAll()
        buffer.append(received("A\nB", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["A\n", "B"]))
        #expect(buffer.entries.allSatisfy { !$0.isTruncated })
        #expect(buffer.entries.allSatisfy { $0.date == secondDate })
    }

    @Test("TXとSYSの大きなイベントもバイト上限で先頭を省略する", arguments: [SerialDirection.transmitted, .system])
    func truncateLargeNonReceiveEvent(direction: SerialDirection) {
        var buffer = SerialLogBuffer(maximumBytes: 4)
        let event = SerialLogEntry(date: firstDate, direction: direction, data: Data("0123456789".utf8))

        buffer.append(event)

        #expect(buffer.entries.map(\.data) == dataLines(["6789"]))
        #expect(buffer.entries.first?.id == event.id)
        #expect(buffer.entries.first?.date == firstDate)
        #expect(buffer.entries.first?.direction == direction)
        #expect(buffer.entries.first?.isTruncated == true)
    }

    @Test("バイト上限と行数上限を同時に適用する")
    func enforceBothRetentionLimits() {
        var buffer = SerialLogBuffer(maximumEntries: 2, maximumBytes: 6)
        buffer.append(received("A\nB\nC\n", at: firstDate))
        #expect(buffer.entries.map(\.data) == dataLines(["B\n", "C\n"]))

        buffer.append(received("0123456789", at: secondDate))

        #expect(buffer.entries.map(\.data) == dataLines(["456789"]))
        #expect(buffer.entries.first?.isTruncated == true)
        #expect(buffer.entries.first?.date == secondDate)
    }

    private func received(_ text: String, at date: Date) -> SerialLogEntry {
        SerialLogEntry(date: date, direction: .received, data: Data(text.utf8))
    }

    private func dataLines(_ lines: [String]) -> [Data] {
        lines.map { Data($0.utf8) }
    }
}
