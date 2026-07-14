import Foundation

public enum SerialPortDiscovery {
    public static func availablePorts(in directory: String = "/dev") -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names
            .filter { $0.hasPrefix("cu.") }
            .map { directory + "/" + $0 }
            .sorted { lhs, rhs in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }
}
