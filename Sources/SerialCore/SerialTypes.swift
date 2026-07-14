import Foundation

public enum SerialParity: String, CaseIterable, Identifiable, Sendable {
    case none
    case even
    case odd

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .even: "偶数"
        case .odd: "奇数"
        }
    }
}

public enum SerialFlowControl: String, CaseIterable, Identifiable, Sendable {
    case none
    case hardware
    case software

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .hardware: "RTS/CTS"
        case .software: "XON/XOFF"
        }
    }
}

public enum LineEnding: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case lf
    case cr
    case crlf

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .none: "なし"
        case .lf: "LF"
        case .cr: "CR"
        case .crlf: "CR + LF"
        }
    }

    public var data: Data {
        switch self {
        case .none: Data()
        case .lf: Data([0x0A])
        case .cr: Data([0x0D])
        case .crlf: Data([0x0D, 0x0A])
        }
    }
}

public enum DataDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case ascii
    case hex
    case asciiAndHex

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .ascii: "ASCII"
        case .hex: "HEX"
        case .asciiAndHex: "ASCII + HEX"
        }
    }
}

public enum SendFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case ascii
    case hex

    public var id: Self { self }
    public var displayName: String { rawValue.uppercased() }
}

public struct SerialConfiguration: Equatable, Sendable {
    public static let supportedBaudRates = [
        300, 600, 1_200, 2_400, 4_800, 9_600, 14_400, 19_200,
        28_800, 38_400, 57_600, 115_200, 230_400
    ]

    public var path: String
    public var baudRate: Int
    public var dataBits: Int
    public var parity: SerialParity
    public var stopBits: Int
    public var flowControl: SerialFlowControl

    public init(
        path: String = "",
        baudRate: Int = 115_200,
        dataBits: Int = 8,
        parity: SerialParity = .none,
        stopBits: Int = 1,
        flowControl: SerialFlowControl = .none
    ) {
        self.path = path
        self.baudRate = baudRate
        self.dataBits = dataBits
        self.parity = parity
        self.stopBits = stopBits
        self.flowControl = flowControl
    }

    public var shortDescription: String {
        let parityCode = switch parity {
        case .none: "N"
        case .even: "E"
        case .odd: "O"
        }
        return "\(baudRate) \(dataBits)\(parityCode)\(stopBits)"
    }
}

public enum SerialDirection: String, Sendable {
    case received = "RX"
    case transmitted = "TX"
    case system = "SYS"
}

public struct SerialLogEntry: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let direction: SerialDirection
    public let data: Data

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        direction: SerialDirection,
        data: Data
    ) {
        self.id = id
        self.date = date
        self.direction = direction
        self.data = data
    }
}

public enum SerialInputError: LocalizedError, Equatable {
    case empty
    case invalidHexToken(String)

    public var errorDescription: String? {
        switch self {
        case .empty:
            "送信データが空です。"
        case .invalidHexToken(let token):
            "「\(token)」は16進数の1バイトとして解釈できません。"
        }
    }
}
