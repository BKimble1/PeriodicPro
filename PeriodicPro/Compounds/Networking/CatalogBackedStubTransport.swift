import Foundation

/// A PubChem stand-in for UI tests and screenshots, answering from the
/// bundled catalog in PubChem's own JSON shapes.
///
/// A UI test cannot depend on a network. Launching with
/// `-compoundNetworkStub` routes the client here instead, so a search for
/// "water" or a formula lookup of C2H6O goes through the real request and
/// parsing code and gets a deterministic, offline answer. Nothing the app
/// ships to a learner ever uses this.
struct CatalogBackedStubTransport: NetworkTransport {
    let catalog: CompoundCatalog

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let parts = url.path.split(separator: "/").map(String.init)
        // …/rest/pug/compound/<domain>/<identifier>/<what>/…
        guard let index = parts.firstIndex(of: "compound"), parts.count > index + 3 else {
            return try respond(status: 404, json: Self.fault, url: url)
        }
        let domain = parts[index + 1]
        let identifier = parts[index + 2].removingPercentEncoding ?? parts[index + 2]
        let what = parts[index + 3]

        switch (domain, what) {
        case ("name", "cids"):
            let hits = catalog.search(identifier, limit: 6).compactMap(\.pubChemCID)
            guard !hits.isEmpty else { return try respond(status: 404, json: Self.fault, url: url) }
            return try respond(json: ["IdentifierList": ["CID": hits]], url: url)
        case ("fastformula", "cids"):
            let hits = catalog.compounds(hillFormula: identifier).compactMap(\.pubChemCID)
            guard !hits.isEmpty else { return try respond(status: 404, json: Self.fault, url: url) }
            return try respond(json: ["IdentifierList": ["CID": hits]], url: url)
        case ("cid", "property"):
            let cids = identifier.split(separator: ",").compactMap { Int($0) }
            let rows = cids.compactMap(catalog.compound(cid:)).map(Self.propertyRow)
            guard !rows.isEmpty else { return try respond(status: 404, json: Self.fault, url: url) }
            return try respond(json: ["PropertyTable": ["Properties": rows]], url: url)
        case ("cid", "JSON"):
            guard let cid = Int(identifier), let compound = catalog.compound(cid: cid),
                  let structure = compound.structure else {
                return try respond(status: 404, json: Self.fault, url: url)
            }
            let wants3D = url.query?.contains("record_type=3d") == true
            if wants3D, !structure.is3D {
                return try respond(status: 404, json: Self.fault, url: url)
            }
            return try respond(json: Self.record(compound, structure: structure, threeD: wants3D), url: url)
        default:
            return try respond(status: 404, json: Self.fault, url: url)
        }
    }

    private static let fault: [String: Any] = [
        "Fault": ["Code": "PUGREST.NotFound", "Message": "No CID found",
                  "Details": ["No CID found that matches the given name"]],
    ]

    private static func propertyRow(_ compound: ChemicalCompound) -> [String: Any] {
        var row: [String: Any] = [
            "CID": compound.pubChemCID ?? 0,
            "MolecularFormula": compound.hillFormula,
            "Title": compound.preferredName,
            "Charge": compound.charge,
        ]
        if let mass = compound.molarMass { row["MolecularWeight"] = String(format: "%.2f", mass) }
        if let iupac = compound.iupacName { row["IUPACName"] = iupac }
        return row
    }

    private static func record(_ compound: ChemicalCompound, structure: CompoundStructure,
                               threeD: Bool) -> [String: Any] {
        let aids = structure.atoms.map { $0.id + 1 }
        var atoms: [String: Any] = ["aid": aids, "element": structure.atoms.map(\.atomicNumber)]
        let charges = structure.atoms.filter { $0.formalCharge != 0 }
            .map { ["aid": $0.id + 1, "value": $0.formalCharge] }
        if !charges.isEmpty { atoms["charge"] = charges }
        var body: [String: Any] = [
            "id": ["id": ["cid": compound.pubChemCID ?? 0]],
            "atoms": atoms,
            "charge": compound.charge,
        ]
        if !structure.bonds.isEmpty {
            body["bonds"] = [
                "aid1": structure.bonds.map { $0.from + 1 },
                "aid2": structure.bonds.map { $0.to + 1 },
                "order": structure.bonds.map { $0.isContact ? 7 : $0.order },
            ]
        }
        var conformer: [String: Any] = ["x": structure.atoms.map(\.x), "y": structure.atoms.map(\.y)]
        if threeD { conformer["z"] = structure.atoms.map(\.z) }
        body["coords"] = [["type": threeD ? [2, 5, 10] : [1, 5], "aid": aids, "conformers": [conformer]]]
        return ["PC_Compounds": [body]]
    }

    private func respond(status: Int = 200, json: [String: Any], url: URL) throws -> (Data, HTTPURLResponse) {
        let data = try JSONSerialization.data(withJSONObject: json)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}
