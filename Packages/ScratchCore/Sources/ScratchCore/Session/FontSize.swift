/// The note font size, shared by every note and remembered between launches (spec §6.4).
///
/// It is 13 pt by default and moves in 1 pt steps between 9 pt and 32 pt. Every function returns a size inside that
/// range, so a size that came from a damaged file or from arithmetic can be passed through ``clamped(_:)`` and used.
public enum FontSize {
    /// The size ⌘0 returns to.
    public static let standard: Double = 13
    /// The smallest size ⌘− reaches.
    public static let minimum: Double = 9
    /// The largest size ⌘+ reaches.
    public static let maximum: Double = 32

    /// `size` plus one point, stopping at ``maximum``.
    public static func larger(_ size: Double) -> Double { clamped(size + 1) }

    /// `size` minus one point, stopping at ``minimum``.
    public static func smaller(_ size: Double) -> Double { clamped(size - 1) }

    /// `size` moved into ``minimum``...``maximum``. A size that is not a number becomes ``standard``.
    public static func clamped(_ size: Double) -> Double {
        guard !size.isNaN else { return standard }
        return min(max(size, minimum), maximum)
    }
}
