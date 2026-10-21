import Foundation

/// Whether bytes are one JSON document, an object or an array (RFC 8259), with no comments in it.
///
/// `CodeDetector` asks this instead of `JSONSerialization`, which is not the same on every platform: Foundation on
/// Linux accepts a trailing comma and the one on macOS does not, and a detector that answers differently on the two
/// would break the tests on one of them.
enum JSONShape {
    /// The deepest nesting that is followed: a text of `[[[[…` is not a document, and must not use up the stack.
    private static let maximumDepth = 256

    static func isDocument(_ bytes: [UInt8]) -> Bool {
        var scanner = Scanner(bytes: bytes)
        scanner.skipSpace()
        guard scanner.index < bytes.count, bytes[scanner.index] == 0x7B || bytes[scanner.index] == 0x5B else {
            return false
        }
        guard scanner.value() else { return false }
        scanner.skipSpace()
        return scanner.index == bytes.count
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        var depth = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func skipSpace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
                index += 1
            }
        }

        private func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func value() -> Bool {
            skipSpace()
            guard let byte = peek() else { return false }
            switch byte {
            case 0x7B: return object()
            case 0x5B: return array()
            case 0x22: return string()
            case 0x74: return literal("true")
            case 0x66: return literal("false")
            case 0x6E: return literal("null")
            default: return number()
            }
        }

        private mutating func literal(_ word: StaticString) -> Bool {
            let length = word.utf8CodeUnitCount
            guard index + length <= bytes.count, Array(bytes[index..<(index + length)]).hasPrefix(word) else {
                return false
            }
            index += length
            return true
        }

        private mutating func object() -> Bool {
            depth += 1
            defer { depth -= 1 }
            guard depth <= JSONShape.maximumDepth else { return false }
            index += 1
            skipSpace()
            if peek() == 0x7D {
                index += 1
                return true
            }
            while true {
                skipSpace()
                guard peek() == 0x22, string() else { return false }
                skipSpace()
                guard peek() == 0x3A else { return false }
                index += 1
                guard value() else { return false }
                skipSpace()
                switch peek() {
                case 0x2C: index += 1
                case 0x7D:
                    index += 1
                    return true
                default: return false
                }
            }
        }

        private mutating func array() -> Bool {
            depth += 1
            defer { depth -= 1 }
            guard depth <= JSONShape.maximumDepth else { return false }
            index += 1
            skipSpace()
            if peek() == 0x5D {
                index += 1
                return true
            }
            while true {
                guard value() else { return false }
                skipSpace()
                switch peek() {
                case 0x2C: index += 1
                case 0x5D:
                    index += 1
                    return true
                default: return false
                }
            }
        }

        private mutating func string() -> Bool {
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x22 {
                    index += 1
                    return true
                }
                if byte < 0x20 { return false }
                if byte == 0x5C {
                    index += 1
                    guard let escaped = peek() else { return false }
                    if escaped == 0x75 {
                        guard index + 4 < bytes.count,
                            bytes[(index + 1)...(index + 4)].allSatisfy({ Byte.isHexDigit($0) })
                        else { return false }
                        index += 4
                    } else if ![0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(escaped) {
                        return false
                    }
                }
                index += 1
            }
            return false
        }

        private mutating func number() -> Bool {
            if peek() == 0x2D { index += 1 }
            guard let first = peek(), Byte.isDigit(first) else { return false }
            if first == 0x30 {
                index += 1
            } else {
                while let digit = peek(), Byte.isDigit(digit) {
                    index += 1
                }
            }
            if peek() == 0x2E {
                index += 1
                guard let digit = peek(), Byte.isDigit(digit) else { return false }
                while let digit = peek(), Byte.isDigit(digit) {
                    index += 1
                }
            }
            if peek() == 0x65 || peek() == 0x45 {
                index += 1
                if peek() == 0x2B || peek() == 0x2D { index += 1 }
                guard let digit = peek(), Byte.isDigit(digit) else { return false }
                while let digit = peek(), Byte.isDigit(digit) {
                    index += 1
                }
            }
            return true
        }
    }
}
