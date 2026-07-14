import Foundation
import Testing
@testable import SerialCore

@Suite("シリアルデータ変換")
struct DataFormattingTests {
    @Test("ASCII送信では選択した改行コードを末尾へ追加する")
    func asciiWithLineEnding() throws {
        let data = try SerialDataFormatter.data(
            from: "status",
            format: .ascii,
            lineEnding: .crlf
        )

        #expect(data == Data([0x73, 0x74, 0x61, 0x74, 0x75, 0x73, 0x0D, 0x0A]))
    }

    @Test("空白・カンマ・0x接頭辞を含むHEX入力を解釈する")
    func parseHex() throws {
        let data = try SerialDataFormatter.parseHex("0x7E, 00 ff 0D 0a")
        #expect(data == Data([0x7E, 0x00, 0xFF, 0x0D, 0x0A]))
    }

    @Test("不正なHEX入力では原因のトークンを返す")
    func rejectInvalidHex() {
        #expect(throws: SerialInputError.invalidHexToken("GG")) {
            try SerialDataFormatter.parseHex("7E GG")
        }
    }

    @Test("HEX表示は2桁大文字の空白区切りになる")
    func formatHex() {
        let text = SerialDataFormatter.hexString(from: Data([0x00, 0x0A, 0xFF]))
        #expect(text == "00 0A FF")
    }

    @Test("ASCII表示は制御不能なバイトを可視化する")
    func formatASCII() {
        let text = SerialDataFormatter.asciiString(from: Data([0x41, 0x00, 0x42, 0x0A]))
        #expect(text == "A·B\n")
    }

    @Test("ASCII表示ではCRLFを1回の改行として扱う")
    func normalizeCRLFForDisplay() {
        let text = SerialDataFormatter.string(
            from: Data([0x41, 0x0D, 0x0A, 0x42]),
            mode: .ascii
        )
        #expect(text == "A\nB")
    }

    @Test("保存用ASCIIはCRLFを区別できる状態で維持する")
    func preserveCRLFForPersistence() {
        let text = SerialDataFormatter.asciiString(from: Data([0x41, 0x0D, 0x0A, 0x42]))
        #expect(text == "A\r\nB")
    }

    @Test("制御コードを表示用ラベルへ変換する")
    func formatControlCodeLabels() {
        #expect(SerialDataFormatter.controlCodeLabel(for: 0x00) == "NUL")
        #expect(SerialDataFormatter.controlCodeLabel(for: 0x09) == "TAB")
        #expect(SerialDataFormatter.controlCodeLabel(for: 0x0A) == "LF")
        #expect(SerialDataFormatter.controlCodeLabel(for: 0x0D) == "CR")
        #expect(SerialDataFormatter.controlCodeLabel(for: 0x1B) == "ESC")
        #expect(SerialDataFormatter.controlCodeLabel(for: 0x7F) == "DEL")
        #expect(SerialDataFormatter.controlCodeLabel(for: 0x41) == nil)
    }
}
