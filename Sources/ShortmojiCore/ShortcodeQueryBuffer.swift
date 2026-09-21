import Foundation

public struct ShortcodeQueryBuffer: Sendable {
    public private(set) var value: String?

    public init() {}

    public var isActive: Bool { value != nil }

    public mutating func begin() {
        value = ":"
    }

    @discardableResult
    public mutating func append(_ characters: String, maximumLength: Int = 48) -> String? {
        guard var value, value.count < maximumLength else { return nil }
        value.append(characters)
        self.value = value
        return value
    }

    @discardableResult
    public mutating func deleteBackward() -> String? {
        guard var value else { return nil }
        if value.count <= 1 {
            self.value = nil
        } else {
            value.removeLast()
            self.value = value
        }
        return self.value
    }

    public mutating func reset() {
        value = nil
    }
}
