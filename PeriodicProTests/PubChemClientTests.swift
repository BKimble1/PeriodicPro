import Foundation
import Testing
@testable import PeriodicPro

/// Answers a fixed error for every request.
private struct FailingTransport: NetworkTransport {
    let error: Error

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw error
    }
}

/// Fails a set number of times, then hands over to a stub.
private final class FlakyTransport: NetworkTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var failuresLeft: Int
    private let failureStatus: Int
    private let failureBody: Data
    private let then: StubTransport
    private(set) var attempts = 0

    init(failures: Int, status: Int, body: Data, then: StubTransport) {
        failuresLeft = failures
        failureStatus = status
        failureBody = body
        self.then = then
    }

    /// Counts the attempt and decides whether it fails, under the lock, in a
    /// synchronous helper so no lock is taken inside async code.
    private func recordAttempt() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        attempts += 1
        let shouldFail = failuresLeft > 0
        if shouldFail { failuresLeft -= 1 }
        return shouldFail
    }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let shouldFail = recordAttempt()
        guard shouldFail, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: failureStatus, httpVersion: nil,
                                             headerFields: nil) else {
            return try await then.perform(request)
        }
        return (failureBody, response)
    }
}

/// The PubChem client against fixtures: parsing, fallbacks, errors and the
/// rules that keep it honest. No test here touches the network.
@Suite("PubChem client")
struct PubChemClientTests {
    private func client(_ routes: [StubTransport.Route], retries: Int = 0) -> (PubChemClient, StubTransport) {
        let transport = StubTransport(routes: routes)
        return (PubChemClient(transport: transport, maximumRetries: retries, minimumGap: .zero), transport)
    }

    private func route(_ pathContains: String, _ fixture: String, status: Int = 200) -> StubTransport.Route {
        StubTransport.Route(pathContains: pathContains, status: status, body: Fixtures.data(fixture))
    }

    @Test("A name search returns the matching compound with its properties")
    func nameSearch() async throws {
        let (client, transport) = client([
            route("name/water/cids", "pubchem-name-water-cids"),
            route("cid/962/property", "pubchem-name-water-properties"),
        ])
        let hits = try await client.search(name: "water")
        #expect(hits.map(\.cid) == [962])
        #expect(hits.first?.name == "Water")
        #expect(hits.first?.hillFormula == "H2O")
        #expect(hits.first?.molarMass == 18.02)
        #expect(hits.first?.iupacName == "oxidane")
        #expect(transport.requestedPaths.count == 2)
        #expect(transport.requestedPaths.first?.contains("compound/name/water/cids/JSON") == true)
    }

    @Test("A formula search returns every neutral match, never just the first")
    func formulaSearchReturnsAllMatches() async throws {
        let (client, _) = client([
            route("fastformula/C2H6O/cids", "pubchem-formula-C2H6O-cids"),
            route("cid/702,8254/property", "pubchem-cids-702-8254-properties"),
        ])
        let hits = try await client.search(hillFormula: "C2H6O")
        #expect(hits.count == 2)
        #expect(Set(hits.map(\.name)) == ["Ethanol", "Dimethyl ether"])
        #expect(hits.allSatisfy { $0.hillFormula == "C2H6O" && $0.charge == 0 })
    }

    @Test("A 3D record parses into atoms, bonds and coordinates")
    func parses3DRecord() async throws {
        let (client, transport) = client([
            route("cid/962/JSON?record_type=3d", "pubchem-cid-962-3d"),
        ])
        let fetched = try await client.structure(cid: 962)
        let structure = try #require(fetched)
        #expect(structure.is3D)
        #expect(structure.source == .pubChem3D)
        #expect(structure.atoms.map(\.atomicNumber) == [8, 1, 1])
        #expect(structure.bonds.count == 2)
        #expect(structure.bonds.allSatisfy { $0.order == 1 && !$0.isContact })
        #expect(structure.atoms.contains { $0.z != 0 || $0.x != 0 || $0.y != 0 })
        #expect(transport.requestedPaths.count == 1, "a 3D hit must not also fetch the 2D record")
    }

    @Test("Without a conformer the client falls back to the authentic 2D record, labeled as 2D")
    func fallsBackTo2D() async throws {
        let (client, transport) = client([
            route("cid/5234/JSON?record_type=3d", "pubchem-fault-no-3d", status: 404),
            route("cid/5234/JSON", "pubchem-cid-5234-2d"),
        ])
        let fetched = try await client.structure(cid: 5234)
        let structure = try #require(fetched)
        #expect(!structure.is3D)
        #expect(structure.source == .pubChem2D)
        #expect(structure.source.representationLabel == "2D structure")
        #expect(structure.atoms.count == 27)
        #expect(structure.atoms.allSatisfy { $0.z == 0 })
        #expect(structure.atoms.filter { $0.formalCharge == 1 }.count == 14)
        #expect(structure.atoms.filter { $0.formalCharge == -1 }.count == 13)
        #expect(transport.requestedPaths.count == 2)
    }

    @Test("Bond orders come through: caffeine has double bonds")
    func bondOrders() async throws {
        let (client, _) = client([route("cid/2519/JSON?record_type=3d", "pubchem-cid-2519-3d")])
        let fetched = try await client.structure(cid: 2519)
        let structure = try #require(fetched)
        #expect(structure.atoms.count == 24)
        #expect(structure.bonds.contains { $0.order == 2 })
        #expect(structure.bonds.allSatisfy { (1...3).contains($0.order) })
    }

    @Test("A single-atom record with no bonds and no coordinates still parses")
    func missingFields() async throws {
        let (client, _) = client([
            route("cid/5462222/JSON?record_type=3d", "pubchem-fault-no-3d", status: 404),
            route("cid/5462222/JSON", "pubchem-cid-missing-fields"),
        ])
        let fetched = try await client.structure(cid: 5462222)
        let structure = try #require(fetched)
        #expect(structure.atoms.map(\.atomicNumber) == [18])
        #expect(structure.bonds.isEmpty)
        #expect(!structure.is3D)
    }

    @Test("The full compound assembles from properties plus structure")
    func fullCompound() async throws {
        let (client, _) = client([
            route("cid/962/property", "pubchem-name-water-properties"),
            route("cid/962/JSON?record_type=3d", "pubchem-cid-962-3d"),
        ])
        let water = try await client.compound(cid: 962)
        #expect(water.id == "pubchem-962")
        #expect(water.preferredName == "Water")
        #expect(water.formula == "H2O")
        #expect(water.hillFormula == "H2O")
        #expect(water.dataSource == .pubChem)
        #expect(water.bondingClass == .unknown, "PubChem does not classify bonding, so neither does the app")
        #expect(water.tags.isEmpty)
        #expect(water.structure?.is3D == true)
        #expect(water.attribution == "Data source: PubChem, CID 962")
    }

    @Test("Malformed JSON is reported, not crashed on")
    func malformed() async {
        let (client, _) = client([route("cid/962/property", "pubchem-malformed")])
        await #expect(throws: PubChemError.self) {
            _ = try await client.candidates(cids: [962])
        }
    }

    @Test("Not found is its own error, with the honest message")
    func notFound() async {
        let (client, _) = client([route("name/unobtainium/cids", "pubchem-fault-notfound", status: 404)])
        do {
            _ = try await client.search(name: "unobtainium")
            Issue.record("expected notFound")
        } catch let error as PubChemError {
            #expect(error == .notFound)
            #expect(error.userMessage == "No known PubChem match found.")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("Offline and timeout map to their own errors")
    func offlineAndTimeout() async {
        let offline = PubChemClient(transport: StubTransport(), maximumRetries: 0, minimumGap: .zero)
        do {
            _ = try await offline.search(name: "water")
            Issue.record("expected offline")
        } catch let error as PubChemError {
            #expect(error == .offline)
        } catch {
            Issue.record("unexpected \(error)")
        }

        let slow = PubChemClient(transport: FailingTransport(error: URLError(.timedOut)),
                                 maximumRetries: 0, minimumGap: .zero)
        do {
            _ = try await slow.search(name: "water")
            Issue.record("expected timeout")
        } catch let error as PubChemError {
            #expect(error == .timeout)
            #expect(error.isRetryable)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("A busy server is retried with backoff, then answered")
    func retriesWhenBusy() async throws {
        let stub = StubTransport(routes: [
            route("name/water/cids", "pubchem-name-water-cids"),
            route("cid/962/property", "pubchem-name-water-properties"),
        ])
        let flaky = FlakyTransport(failures: 2, status: 503, body: Fixtures.data("pubchem-fault-busy"), then: stub)
        let client = PubChemClient(transport: flaky, maximumRetries: 2, minimumGap: .zero)
        let hits = try await client.search(name: "water")
        #expect(hits.first?.cid == 962)
        #expect(flaky.attempts == 4, "two failures, the successful cids call, then the properties call")

        let exhausted = FlakyTransport(failures: 5, status: 503, body: Fixtures.data("pubchem-fault-busy"),
                                       then: stub)
        let givesUp = PubChemClient(transport: exhausted, maximumRetries: 1, minimumGap: .zero)
        do {
            _ = try await givesUp.search(name: "water")
            Issue.record("expected rateLimited")
        } catch let error as PubChemError {
            #expect(error == .rateLimited)
            #expect(exhausted.attempts == 2)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("A superseded search stops rather than finishing")
    func cancellation() async {
        let stub = StubTransport(routes: [route("name/water/cids", "pubchem-name-water-cids")])
        stub.latency = .milliseconds(400)
        let client = PubChemClient(transport: stub, maximumRetries: 0, minimumGap: .zero)
        let task = Task { try await client.search(name: "water") }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("a canceled search must not complete")
        } catch let error as PubChemError {
            #expect(error == .canceled)
        } catch is CancellationError {
            // Canceled before the request was even built: also correct.
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("Queries that are not names or formulas never reach the network")
    func queryHygiene() async {
        #expect(!PubChemClient.isPlausibleName("8"))
        #expect(!PubChemClient.isPlausibleName("O"))
        #expect(!PubChemClient.isPlausibleName(""))
        #expect(PubChemClient.isPlausibleName("sodium chloride"))
        #expect(PubChemClient.isPlausibleName("2-propanol"))
        #expect(PubChemClient.isPlausibleFormula("C2H6O"))
        #expect(!PubChemClient.isPlausibleFormula("c2h6o"))
        #expect(!PubChemClient.isPlausibleFormula("H2O; DROP"))
        #expect(!CompoundSearchModel.shouldQueryRemote("26"))
        #expect(!CompoundSearchModel.shouldQueryRemote("Fe"))
        #expect(CompoundSearchModel.shouldQueryRemote("water"))

        let (client, transport) = client([])
        await #expect(throws: PubChemError.invalidQuery) { _ = try await client.search(name: "8") }
        await #expect(throws: PubChemError.invalidQuery) { _ = try await client.search(hillFormula: "h2o") }
        #expect(transport.requestedPaths.isEmpty)
    }

    @Test("Fault codes map to the right errors")
    func faultMapping() {
        #expect(PubChemClient.map(faultCode: "PUGREST.NotFound", status: 200) == .notFound)
        #expect(PubChemClient.map(faultCode: "PUGREST.ServerBusy", status: 200) == .rateLimited)
        #expect(PubChemClient.map(faultCode: "PUGREST.Timeout", status: 200) == .timeout)
        #expect(PubChemClient.map(faultCode: "PUGREST.BadRequest", status: 200) == .invalidQuery)
        #expect(PubChemClient.map(URLError(.notConnectedToInternet)) == .offline)
        #expect(PubChemClient.map(URLError(.timedOut)) == .timeout)
    }

    @Test("The catalog-backed stub speaks PubChem's own shapes end to end")
    func catalogStub() async throws {
        let client = PubChemClient(transport: CatalogBackedStubTransport(catalog: TestCompounds.catalog),
                                   maximumRetries: 0, minimumGap: .zero)
        let water = try await client.search(name: "water")
        #expect(water.first?.name == "Water")
        let ethers = try await client.search(hillFormula: "C2H6O")
        #expect(ethers.count == 2)
        let salt = try await client.compound(cid: 5234)
        #expect(salt.preferredName == "Sodium chloride")
        #expect(salt.structure?.is3D == true, "the lattice is 3D data")
        await #expect(throws: PubChemError.notFound) { _ = try await client.search(name: "unobtainium") }
    }
}

@MainActor
@Suite("Compound cache and store")
struct CompoundStoreTests {
    @Test("A fetched compound is cached and served locally afterwards")
    func cacheRoundTrip() async throws {
        let container = try #require(PersistenceController.makeInMemoryContainer())
        let transport = StubTransport(routes: [
            StubTransport.Route(pathContains: "cid/2519/property",
                                body: Fixtures.data("pubchem-cids-2519-properties")),
            StubTransport.Route(pathContains: "cid/2519/JSON?record_type=3d",
                                body: Fixtures.data("pubchem-cid-2519-3d")),
        ])
        let client = PubChemClient(transport: transport, maximumRetries: 0, minimumGap: .zero)
        let store = CompoundStore(container: container, catalog: CompoundCatalog(compounds: []), client: client)
        let candidate = CompoundMatchCandidate(cid: 2519, name: "Caffeine", hillFormula: "C8H10N4O2",
                                               molarMass: 194.19, iupacName: nil)
        let caffeine = try await store.resolve(candidate)
        #expect(caffeine.preferredName == "Caffeine")
        #expect(transport.requestedPaths.count == 2)

        let again = try await store.resolve(candidate)
        #expect(again == caffeine)
        #expect(transport.requestedPaths.count == 2, "the second resolve must come from the cache")

        // A new store on the same container reads it back.
        let reopened = CompoundStore(container: container, catalog: CompoundCatalog(compounds: []), client: client)
        #expect(reopened.compound(cid: 2519)?.preferredName == "Caffeine")
        #expect(reopened.cachedCompounds.count == 1)
    }

    @Test("A corrupt cache row is discarded rather than served")
    func corruptCacheRow() throws {
        let container = try #require(PersistenceController.makeInMemoryContainer())
        let cache = CompoundCache(container: container)
        cache.store(TestCompounds.compound("Water"))
        let context = container.mainContext
        let bad = CachedCompoundRecord(compoundID: "pubchem-1", pubChemCID: 1, payload: Data("nonsense".utf8),
                                       fetchedAt: Date())
        context.insert(bad)
        try context.save()
        let reopened = CompoundCache(container: container)
        #expect(reopened.compound(id: "pubchem-962") != nil)
        #expect(reopened.compound(id: "pubchem-1") == nil)
        #expect(reopened.all.count == 1)
    }

    @Test("With online lookup disabled the store never asks and says why")
    func offlineStore() async {
        let transport = StubTransport()
        let store = CompoundStore(container: nil, catalog: TestCompounds.catalog,
                                  client: PubChemClient(transport: transport, maximumRetries: 0, minimumGap: .zero),
                                  isOnlineLookupEnabled: false)
        let remote = try? await store.remoteSearch(name: "water")
        #expect(remote?.isEmpty == true)
        #expect(transport.requestedPaths.isEmpty)
        #expect(store.localSearch("water").first?.preferredName == "Water")
        #expect(store.localCandidates(hillFormula: "C2H6O").count == 2)
        let unknown = CompoundMatchCandidate(cid: 1, name: "x", hillFormula: "X", molarMass: nil, iupacName: nil)
        await #expect(throws: PubChemError.offline) { _ = try await store.resolve(unknown) }
    }
}
