import Foundation

public enum SerialDataFormatter {
    public static func data(
        from input: String,
        format: SendFormat,
        lineEnding: LineEnding
    ) throws -> Data {
        guard !input.isEmpty else { throw SerialInputError.empty }

        switch format {
        case .ascii:
            var result = Data(input.utf8)
            result.append(lineEnding.data)
            return result
        case .hex:
            return try parseHex(input)
        }
    }

    public static func parseHex(_ input: String) throws -> Data {
        let normalized = input
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        let rawTokens = normalized.split(separator: " ").map(String.init)
        guard !rawTokens.isEmpty else { throw SerialInputError.empty }

        var bytes: [UInt8] = []
        for rawToken in rawTokens {
            let token: String
            if rawToken.lowercased().hasPrefix("0x") {
                token = String(rawToken.dropFirst(2))
            } else {
                token = rawToken
            }

            guard !token.isEmpty, token.count <= 2, let byte = UInt8(token, radix: 16) else {
                throw SerialInputError.invalidHexToken(rawToken)
            }
            bytes.append(byte)
        }
        return Data(bytes)
    }

    public static func string(from data: Data, mode: DataDisplayMode) -> String {
        switch mode {
        case .ascii:
            asciiDisplayString(from: data)
        case .hex:
            hexString(from: data)
        case .asciiAndHex:
            "\(asciiDisplayString(from: data))    [\(hexString(from: data))]"
        }
    }

    public static func asciiDisplayString(from data: Data) -> String {
        let bytes = [UInt8](data)
        var result = ""
        result.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0x0D:
                result.append("\n")
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    index += 2
                } else {
                    index += 1
                }
            case 0x0A:
                result.append("\n")
                index += 1
            case 0x09:
                result.append("\t")
                index += 1
            case 0x20...0x7E:
                result.append(Character(UnicodeScalar(byte)))
                index += 1
            default:
                result.append("·")
                index += 1
            }
        }
        return result
    }

    public static func asciiString(from data: Data) -> String {
        var result = ""
        result.reserveCapacity(data.count)

        for byte in data {
            switch byte {
            case 0x0A:
                result.append("\n")
            case 0x0D:
                if !result.hasSuffix("\n") {
                    result.append("\r")
                }
            case 0x09:
                result.append("\t")
            case 0x20...0x7E:
                result.append(Character(UnicodeScalar(byte)))
            default:
                result.append("·")
            }
        }
        return result
    }

    public static func hexString(from data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public static func controlCodeLabel(for byte: UInt8) -> String? {
        let c0Labels = [
            "NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL",
            "BS", "TAB", "LF", "VT", "FF", "CR", "SO", "SI",
            "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB",
            "CAN", "EM", "SUB", "ESC", "FS", "GS", "RS", "US"
        ]

        if byte < 0x20 {
            return c0Labels[Int(byte)]
        }
        if byte == 0x7F {
            return "DEL"
        }
        return nil
    }

    public static func matchesSearch(data: Data, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        if asciiDisplayString(from: data).localizedCaseInsensitiveContains(query) {
            return true
        }
        if hexString(from: data).localizedCaseInsensitiveContains(query) {
            return true
        }

        let controlLabels = data.compactMap(controlCodeLabel).joined(separator: " ")
        if controlLabels.localizedCaseInsensitiveContains(query) {
            return true
        }

        guard let compactQuery = normalizedHexSearchQuery(query) else { return false }
        let compactData = hexString(from: data).replacingOccurrences(of: " ", with: "")
        return compactData.contains(compactQuery)
    }

    public static func normalizedHexSearchQuery(_ query: String) -> String? {
        let withoutPrefixes = query.replacingOccurrences(
            of: "0x",
            with: "",
            options: .caseInsensitive
        )
        let allowedSeparators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",:-_"))
        guard withoutPrefixes.unicodeScalars.allSatisfy({ scalar in
            scalar.properties.isHexDigit || allowedSeparators.contains(scalar)
        }) else { return nil }

        let compact = withoutPrefixes.filter(\.isHexDigit).uppercased()
        guard compact.count >= 2, compact.count.isMultiple(of: 2) else { return nil }
        return compact
    }

    public static func timestamp(_ date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: date
        )
        let milliseconds = (components.nanosecond ?? 0) / 1_000_000
        return String(
            format: "%02d:%02d:%02d.%03d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            milliseconds
        )
    }

    public static func persistentLogLine(for entry: SerialLogEntry) -> String {
        let body: String
        if entry.direction == .system {
            body = asciiString(from: entry.data)
        } else {
            let ascii = asciiString(from: entry.data)
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\n", with: "\\n")
            body = "\(ascii)    [\(hexString(from: entry.data))]"
        }
        return "\(timestamp(entry.date))  \(entry.direction.rawValue)  \(body)\n"
    }
}
