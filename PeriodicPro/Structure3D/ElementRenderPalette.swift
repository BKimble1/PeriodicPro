import Foundation

/// The color each element's atoms are drawn in, as packed RGB.
///
/// Molecular elements use the conventional CPK-style colors a chemistry
/// student will recognize — red oxygen, blue nitrogen, yellow sulfur. Metals
/// get the color of the metal itself where it has one worth showing — gold,
/// copper, silver, the faint straw of cesium, the blue cast of osmium — and a
/// neutral steel otherwise. The look of the metal comes from the material
/// (`StructureEntityFactory`), which renders metallic scenes as metal; this
/// table is only the tint.
///
/// Kept free of SwiftUI so the scene builder can stamp the tint onto every
/// node and the tests can check it.
enum ElementRenderPalette {
    /// Neutral metallic gray, for every metal without a color of its own.
    static let steel: UInt32 = 0xA9AEB6

    static func tintHex(atomicNumber: Int) -> UInt32? {
        if let explicit = table[atomicNumber] { return explicit }
        if (57...71).contains(atomicNumber) { return 0xB2B8C0 }   // lanthanides
        if (89...99).contains(atomicNumber) { return 0xADB3BB }   // actinides with a known metal
        return nil
    }

    private static let table: [Int: UInt32] = [
        1: 0xE6EAEE, 2: 0xC8F3F6, 3: 0xC9CDD3, 4: 0xBEC3C8, 5: 0xF3B4A8,
        6: 0x4A4F57, 7: 0x3A64E6, 8: 0xE8412F, 9: 0x8FD35B, 10: 0xA8DCEF,
        11: 0xC2C8CF, 12: 0xC6CBD1, 13: 0xD5D9DE, 14: 0xD8C4A8, 15: 0xF08A2A,
        16: 0xE9D23A, 17: 0x3FC94A, 18: 0x7EC9DB, 19: 0xBCC1C8, 20: 0xC0C5CB,
        21: 0xB5BBC3, 22: 0xAAB0B9, 23: 0xA6ACB5, 24: 0xB5BCC6, 25: 0xA3A8B0,
        26: 0x9EA5AE, 27: 0xA6ABB3, 28: 0xB4B9BF, 29: 0xC97F4A, 30: 0xB3B9C1,
        31: 0xB8BEC6, 32: 0x9FB0B4, 33: 0xB48CD9, 34: 0xE0A05A, 35: 0xA83E2E,
        36: 0x64B8CF, 37: 0xB7BCC4, 38: 0xBBC0C7, 39: 0xB1B7BF, 40: 0xB0B6BE,
        41: 0xA8AEB7, 42: 0xA3A9B2, 43: 0xA4AAB2, 44: 0xA6ACB4, 45: 0xB9BEC5,
        46: 0xB7BCC2, 47: 0xCDD1D6, 48: 0xB6BBC2, 49: 0xB4B9C0, 50: 0xB6BBC1,
        51: 0xA48CC2, 52: 0xD4884E, 53: 0x8E3D9E, 54: 0x4AA2B6, 55: 0xE3CF9C,
        56: 0xB4BAC2, 72: 0xADB3BB, 73: 0xA6ACB4, 74: 0x9EA4AC, 75: 0xA1A7AF,
        76: 0x8E9BAB, 77: 0xB2B8BE, 78: 0xD0D4D8, 79: 0xE0B44A, 80: 0xC0C5CC,
        81: 0xA9AFB7, 82: 0x8F959D, 83: 0xC7ABB6, 84: 0xA3A9B1, 86: 0x469CAF,
        88: 0xB1B7BF,
    ]
}
