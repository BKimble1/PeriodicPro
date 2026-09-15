import Foundation

/// One practical, recognisable application of an element.
struct ElementUse: Codable, Hashable, Identifiable, Sendable {
    let title: String
    let detail: String
    let symbolName: String

    var id: String { title }
}

/// A single confirmed chemical element.
///
/// Deliberately named `ChemicalElement` rather than `Element` so it never
/// collides with `Collection.Element` or SwiftUI's generic parameters.
struct ChemicalElement: Codable, Identifiable, Hashable, Sendable {
    // Identity & position
    let atomicNumber: Int
    let symbol: String
    let name: String
    let category: ElementCategory
    let group: Int?
    let period: Int
    let block: String
    let gridX: Int
    let gridY: Int

    // Physical properties
    let atomicMass: Double
    /// `true` when `atomicMass` is the mass number of the most stable isotope
    /// rather than a IUPAC standard atomic weight.
    let atomicMassIsMassNumber: Bool
    let electronConfiguration: String
    let shellElectrons: [Int]
    let phase: MatterPhase
    let meltingPointK: Double?
    let boilingPointK: Double?
    let densityGramsPerCm3: Double?
    let electronegativity: Double?
    let discoveryYear: Int?
    let discoveredBy: String?

    // Editorial
    let tagline: String
    let about: String
    let memoryHook: String
    let structure: ElementStructure
    let elementalForm: String
    let uses: [ElementUse]

    var id: Int { atomicNumber }

    static func == (lhs: ChemicalElement, rhs: ChemicalElement) -> Bool {
        lhs.atomicNumber == rhs.atomicNumber
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(atomicNumber)
    }
}

// MARK: - Derived presentation values

extension ChemicalElement {
    /// Atomic mass formatted for display, e.g. `22.990 u` or `98 u (most stable)`.
    var formattedAtomicMass: String {
        if atomicMassIsMassNumber {
            return "\(Int(atomicMass.rounded())) u"
        }
        return "\(Self.massFormatter.string(from: NSNumber(value: atomicMass)) ?? "\(atomicMass)") u"
    }

    var atomicMassFootnote: String? {
        atomicMassIsMassNumber ? "Mass number of the most stable isotope" : nil
    }

    /// `[Ne] 3s1` rendered with real Unicode superscripts: `[Ne] 3s¹`.
    var formattedElectronConfiguration: String {
        SuperscriptFormatter.applyingSuperscripts(to: electronConfiguration)
    }

    var groupDisplay: String {
        guard let group else { return "—" }
        return "\(group)"
    }

    var blockDisplay: String { "\(block)-block" }

    /// Lanthanides and actinides live on the two detached rows beneath the table.
    var isInnerTransition: Bool { gridY > 7 }

    var discoveryDisplay: String? {
        switch (discoveryYear, discoveredBy) {
        case let (year?, who?): return "\(who), \(year)"
        case let (year?, nil): return "\(year)"
        case let (nil, who?): return who
        default: return nil
        }
    }

    /// Kelvin values converted for the detail screen. Returns `nil` when the
    /// underlying measurement is unknown.
    func temperatureDisplay(_ kelvin: Double?) -> String? {
        guard let kelvin else { return nil }
        let celsius = kelvin - 273.15
        let k = Self.temperatureFormatter.string(from: NSNumber(value: kelvin)) ?? "\(kelvin)"
        let c = Self.temperatureFormatter.string(from: NSNumber(value: celsius)) ?? "\(celsius)"
        return "\(k) K  ·  \(c) °C"
    }

    /// Solids and liquids are shown in g/cm³; gases use the conventional g/L so
    /// the number stays readable instead of collapsing to scientific notation.
    var densityDisplay: String? {
        guard let densityGramsPerCm3 else { return nil }
        if phase == .gas {
            let gramsPerLitre = densityGramsPerCm3 * 1000
            let value = Self.densityFormatter.string(from: NSNumber(value: gramsPerLitre))
                ?? "\(gramsPerLitre)"
            return "\(value) g/L"
        }
        let value = Self.densityFormatter.string(from: NSNumber(value: densityGramsPerCm3))
            ?? "\(densityGramsPerCm3)"
        return "\(value) g/cm³"
    }

    var electronegativityDisplay: String? {
        guard let electronegativity else { return nil }
        let value = Self.densityFormatter.string(from: NSNumber(value: electronegativity)) ?? "\(electronegativity)"
        return "\(value) (Pauling)"
    }

    /// Spoken description used for VoiceOver on every element tile.
    var accessibilityDescription: String {
        "\(name), symbol \(symbol.spelledOutForVoiceOver), atomic number \(atomicNumber), \(category.displayName)"
    }

    private static let massFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 3
        return f
    }()

    private static let temperatureFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    private static let densityFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 3
        return f
    }()

}

extension String {
    /// "Na" -> "N a", so VoiceOver spells the symbol out letter by letter
    /// instead of trying to pronounce it as a word.
    var spelledOutForVoiceOver: String {
        map(String.init).joined(separator: " ")
    }
}

/// Converts the ASCII electron-configuration notation stored in `elements.json`
/// into typographically correct superscripts.
enum SuperscriptFormatter {
    private static let digits: [Character: Character] = [
        "0": "\u{2070}", "1": "\u{00B9}", "2": "\u{00B2}", "3": "\u{00B3}", "4": "\u{2074}",
        "5": "\u{2075}", "6": "\u{2076}", "7": "\u{2077}", "8": "\u{2078}", "9": "\u{2079}",
    ]

    /// Digits that immediately follow an orbital letter (s, p, d, f) become
    /// superscripts; principal quantum numbers preceding a letter do not.
    ///
    /// Expects the space-separated notation stored in `elements.json`
    /// ("[Ne] 3s2 3p4"), which `Tools/validate_elements.py` enforces. Unspaced
    /// notation is ambiguous and is not supported.
    static func applyingSuperscripts(to configuration: String) -> String {
        var output = ""
        output.reserveCapacity(configuration.count)
        var afterOrbitalLetter = false

        for character in configuration {
            if character.isNumber, afterOrbitalLetter {
                output.append(digits[character] ?? character)
                continue
            }
            afterOrbitalLetter = "spdf".contains(character)
            output.append(character)
        }
        return output
    }
}
