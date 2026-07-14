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
            asciiString(from: data)
        case .hex:
            hexString(from: data)
        case .asciiAndHex:
            "\(asciiString(from: data))    [\(hexString(from: data))]"
        }
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
