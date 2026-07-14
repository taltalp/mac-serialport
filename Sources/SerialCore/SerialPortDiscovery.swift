import CoreFoundation
import Foundation
import IOKit

public struct SerialPortInfo: Identifiable, Hashable, Sendable {
    public let path: String
    public let productName: String?
    public let manufacturer: String?
    public let vendorID: Int?
    public let productID: Int?
    public let serialNumber: String?
    public let locationID: UInt32?

    public init(
        path: String,
        productName: String? = nil,
        manufacturer: String? = nil,
        vendorID: Int? = nil,
        productID: Int? = nil,
        serialNumber: String? = nil,
        locationID: UInt32? = nil
    ) {
        self.path = path
        self.productName = productName?.nilIfEmpty
        self.manufacturer = manufacturer?.nilIfEmpty
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber?.nilIfEmpty
        self.locationID = locationID
    }

    public var id: String { path }

    public var deviceName: String {
        productName ?? URL(fileURLWithPath: path).lastPathComponent
    }

    public var menuTitle: String {
        guard let productName else { return path }
        return "\(productName) — \(URL(fileURLWithPath: path).lastPathComponent)"
    }

    public var vendorProductText: String? {
        guard let vendorID, let productID else { return nil }
        return String(format: "%04X:%04X", vendorID, productID)
    }

    public var hasUSBMetadata: Bool {
        productName != nil || manufacturer != nil || vendorID != nil
            || productID != nil || serialNumber != nil || locationID != nil
    }

    public func representsSameDevice(as other: SerialPortInfo) -> Bool {
        if let serialNumber, let otherSerial = other.serialNumber {
            guard serialNumber == otherSerial else { return false }
            return usbIDsAreCompatible(with: other)
        }

        if let locationID, let otherLocation = other.locationID,
           locationID == otherLocation, usbIDsAreCompatible(with: other) {
            return true
        }

        return path == other.path
    }

    private func usbIDsAreCompatible(with other: SerialPortInfo) -> Bool {
        if let vendorID, let otherVendor = other.vendorID, vendorID != otherVendor {
            return false
        }
        if let productID, let otherProduct = other.productID, productID != otherProduct {
            return false
        }
        return true
    }
}

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

    public static func availablePortInfos() -> [SerialPortInfo] {
        let metadata = ioKitPortMetadata()
        return availablePorts().map { path in
            metadata[path] ?? SerialPortInfo(path: path)
        }
    }

    private static func ioKitPortMetadata() -> [String: SerialPortInfo] {
        guard let matchingDictionary = IOServiceMatching("IOSerialBSDClient") else {
            return [:]
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matchingDictionary,
            &iterator
        ) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var result: [String: SerialPortInfo] = [:]
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let path = stringProperty("IOCalloutDevice", entry: service),
               path.hasPrefix("/dev/cu.") {
                result[path] = SerialPortInfo(
                    path: path,
                    productName: searchedStringProperty("USB Product Name", entry: service),
                    manufacturer: searchedStringProperty("USB Vendor Name", entry: service),
                    vendorID: searchedNumberProperty("idVendor", entry: service)?.intValue,
                    productID: searchedNumberProperty("idProduct", entry: service)?.intValue,
                    serialNumber: searchedStringProperty("USB Serial Number", entry: service),
                    locationID: searchedNumberProperty("locationID", entry: service)?.uint32Value
                )
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    private static func stringProperty(_ key: String, entry: io_registry_entry_t) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else { return nil }
        return value as? String
    }

    private static func searchedStringProperty(
        _ key: String,
        entry: io_registry_entry_t
    ) -> String? {
        searchedProperty(key, entry: entry) as? String
    }

    private static func searchedNumberProperty(
        _ key: String,
        entry: io_registry_entry_t
    ) -> NSNumber? {
        searchedProperty(key, entry: entry) as? NSNumber
    }

    private static func searchedProperty(
        _ key: String,
        entry: io_registry_entry_t
    ) -> CFTypeRef? {
        IORegistryEntrySearchCFProperty(
            entry,
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
