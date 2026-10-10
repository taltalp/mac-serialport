import Foundation

/// Display entries grouped by received lines, independently of transport read boundaries.
public struct SerialLogBuffer: Sendable {
    public private(set) var entries: [SerialLogEntry] = []

    private let maximumEntries: Int
    private let maximumBytes: Int
    private var retainedByteCount = 0
    // An unfinished RX line, or a line ending in CR that may still receive its LF.
    private var receivedLineIndex: Int?

    public init(maximumEntries: Int = 5_000, maximumBytes: Int = 20 * 1024 * 1024) {
        precondition(maximumEntries > 0)
        precondition(maximumBytes > 0)
        self.maximumEntries = maximumEntries
        self.maximumBytes = maximumBytes
    }

    public mutating func append(_ entry: SerialLogEntry) {
        if entry.direction == .received {
            appendReceived(entry)
        } else {
            entries.append(entry)
            retainedByteCount += entry.data.count
        }
        trimEntries()
    }

    /// Preserve the visible partial line, but start a new line on the next connection.
    public mutating func finishReceiving() {
        receivedLineIndex = nil
    }

    public mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        receivedLineIndex = nil
        retainedByteCount = 0
    }

    private mutating func appendReceived(_ entry: SerialLogEntry) {
        let data = entry.data
        var cursor = data.startIndex

        while cursor < data.endIndex {
            if let index = receivedLineIndex, entries[index].data.last == 0x0D {
                // CR already completed the line. A following LF belongs to that same ending,
                // including when the two bytes arrive in different reads or UI batches.
                if data[cursor] == 0x0A {
                    appendData(Data([0x0A]), to: index)
                    cursor += 1
                }
                receivedLineIndex = nil
                guard cursor < data.endIndex else { break }
            }

            let start = cursor
            while cursor < data.endIndex {
                let byte = data[cursor]
                cursor += 1
                if byte == 0x0D {
                    if cursor < data.endIndex, data[cursor] == 0x0A {
                        cursor += 1
                    }
                    break
                }
                if byte == 0x0A { break }
            }

            let fragment = Data(data[start..<cursor])
            if let index = receivedLineIndex {
                appendData(fragment, to: index)
                if entry.isTruncated && start == data.startIndex {
                    entries[index].isTruncated = true
                }
            } else {
                entries.append(SerialLogEntry(
                    date: entry.date,
                    direction: .received,
                    data: fragment,
                    isTruncated: entry.isTruncated && start == data.startIndex
                ))
                retainedByteCount += fragment.count
                receivedLineIndex = entries.count - 1
            }

            if fragment.last == 0x0A {
                receivedLineIndex = nil
            }
        }
    }

    private mutating func appendData(_ data: Data, to index: Int) {
        entries[index].data.append(data)
        retainedByteCount += data.count
    }

    private mutating func trimEntries() {
        var removedCount = 0
        while removedCount < entries.count - 1,
              entries.count - removedCount > maximumEntries || retainedByteCount > maximumBytes {
            retainedByteCount -= entries[removedCount].data.count
            removedCount += 1
        }

        if removedCount > 0 {
            entries.removeFirst(removedCount)
            if let index = receivedLineIndex {
                receivedLineIndex = index >= removedCount ? index - removedCount : nil
            }
        }

        if retainedByteCount > maximumBytes {
            // Even an unterminated line is bounded. Keep its identity, first-receive time,
            // and trailing CR so subsequent bytes still join the same logical line.
            let end = entries[0].data.endIndex
            entries[0].data = entries[0].data.subdata(in: (end - maximumBytes)..<end)
            entries[0].isTruncated = true
            retainedByteCount = maximumBytes
        }
    }
}
