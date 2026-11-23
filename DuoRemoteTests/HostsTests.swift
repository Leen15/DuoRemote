import Testing
import Foundation
@testable import DuoRemote

@MainActor
struct HostsTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "hosts-\(UUID().uuidString).json")
    }

    @Test func firstLaunchStartsEmpty() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HostStore(fileURL: url)
        #expect(store.hosts.isEmpty)
    }

    @Test func emptyListStaysEmpty() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = HostStore(fileURL: url)
        first.add(Host(name: "A", hostname: "a", username: "u"))
        for host in first.hosts { first.delete(host) }
        #expect(first.hosts.isEmpty)

        let second = HostStore(fileURL: url)
        #expect(second.hosts.isEmpty)
    }

    @Test func roundTripThroughFile() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HostStore(fileURL: url)
        var extra = Host(name: "Studio", hostname: "studio", port: 5901, username: "user")
        store.add(extra)
        extra.username = "other"
        extra.displayLayout = .twoByTwo
        extra.selectedDisplay = 4
        store.update(extra)

        let reloaded = HostStore(fileURL: url)
        #expect(reloaded.hosts == store.hosts)
        #expect(reloaded.host(withID: extra.id)?.username == "other")
        #expect(reloaded.host(withID: extra.id)?.port == 5901)
    }

    @Test func retryBackoffIsOneTwoFourThenStops() {
        #expect(RetryPolicy.delay(forAttempt: 1) == .seconds(1))
        #expect(RetryPolicy.delay(forAttempt: 2) == .seconds(2))
        #expect(RetryPolicy.delay(forAttempt: 3) == .seconds(4))
        #expect(RetryPolicy.delay(forAttempt: 4) == nil)
        #expect(RetryPolicy.delay(forAttempt: 0) == nil)
    }

    @Test func onlyNetworkAndServerCloseRetry() {
        #expect(RetryPolicy.shouldRetry(.network("x")))
        #expect(RetryPolicy.shouldRetry(.closedByServer))
        #expect(!RetryPolicy.shouldRetry(.authenticationFailed))
        #expect(!RetryPolicy.shouldRetry(nil))
    }

    @Test func oldJSONDecodesWithoutNewFields() throws {
        let json = #"{"id":"6E1C3E5A-2C1B-4B8E-9A55-0F4E4B1E7A11","name":"Mini","hostname":"mini","port":5901,"username":"me"}"#
        let host = try JSONDecoder().decode(Host.self, from: Data(json.utf8))
        #expect(host.name == "Mini" && host.port == 5901 && host.username == "me")
        #expect(host.symbol == nil && host.lastConnected == nil)
        #expect(host.symbolName == "desktopcomputer")
        #expect(host.allowOutsideTailscale == false)
        #expect(host.displayLayout == .single)
        #expect(host.displayGrid.count == 1 && host.selectedDisplay == 0)
    }

    @Test func allowOutsideTailscaleRoundTrips() throws {
        var host = Host(name: "A", hostname: "a", username: "u")
        host.allowOutsideTailscale = true
        let back = try JSONDecoder().decode(Host.self, from: JSONEncoder().encode(host))
        #expect(back.allowOutsideTailscale)
    }

    @Test func displayLayoutAndSelectionRoundTrip() throws {
        var host = Host(name: "Grid", hostname: "grid", username: "u")
        host.displayLayout = .custom
        host.displayColumns = 4
        host.displayRows = 3
        host.selectedDisplay = 11
        let back = try JSONDecoder().decode(Host.self, from: JSONEncoder().encode(host))
        #expect(back == host)
        #expect(back.displayGrid == DisplayGrid(columns: 4, rows: 3))
    }

    @Test func gridRectsAreRowMajor() {
        let rects = DisplayGrid(columns: 2, rows: 2).rects(framebufferSize: CGSize(width: 400, height: 200))
        #expect(rects == [CGRect(x: 0, y: 0, width: 200, height: 100),
                          CGRect(x: 200, y: 0, width: 200, height: 100),
                          CGRect(x: 0, y: 100, width: 200, height: 100),
                          CGRect(x: 200, y: 100, width: 200, height: 100)])
    }

    @Test func oddGridRectsTileWholeFramebuffer() {
        for columns in 1...4 {
            for rows in 1...4 {
                let whole = CGRect(x: 0, y: 0, width: 101, height: 77)
                let rects = DisplayGrid(columns: columns, rows: rows).rects(framebufferSize: whole.size)
                #expect(rects.count == columns * rows)
                #expect(rects.reduce(CGRect.null) { $0.union($1) } == whole)
                #expect(rects.reduce(CGFloat.zero) { $0 + $1.width * $1.height } == whole.width * whole.height)
                for (index, rect) in rects.enumerated() {
                    #expect(rect == rect.integral)
                    for other in rects.dropFirst(index + 1) {
                        let overlap = rect.intersection(other)
                        #expect(overlap.isNull || overlap.isEmpty)
                    }
                }
            }
        }
    }

    @Test func gridBoundsAndEmptyFramebuffer() {
        #expect(DisplayGrid(columns: 0, rows: 20) == DisplayGrid(columns: 1, rows: 4))
        #expect(DisplayGrid(columns: 2, rows: 2).rects(framebufferSize: .zero).isEmpty)
        let tiny = DisplayGrid(columns: 4, rows: 4).rects(framebufferSize: CGSize(width: 1, height: 1))
        #expect(tiny.reduce(CGFloat.zero) { $0 + $1.width * $1.height } == 1)
    }

    @Test func displaySelectionFitsAndMovesPointer() throws {
        let session = VNCSession.demo()
        session.viewport.setBounds(CGSize(width: 400, height: 300), insets: .zero, displayScale: 3)
        session.configureDisplays(grid: DisplayGrid(columns: 2, rows: 2), selection: 0)
        session.selectDisplay(4)
        let size = try #require(session.framebufferSize)
        let rect = session.displayGrid.rects(framebufferSize: size)[3]
        #expect(session.pointer == CGPoint(x: rect.midX, y: rect.midY))
        #expect(session.selectedDisplay == 4)
        session.selectDisplay(0)
        #expect(session.viewport.scale == session.viewport.fitScale)
        session.selectDisplay(99)
        #expect(session.selectedDisplay == 0)
    }

    @Test func advancingDisplaySelectionWrapsToAll() {
        let session = VNCSession.demo()
        for count in 1...4 {
            session.configureDisplays(grid: DisplayGrid(columns: count, rows: 1), selection: 0)
            for _ in 0..<2 {
                if count > 1 {
                    for number in 1...count {
                        session.selectDisplay(session.selectedDisplay + 1)
                        #expect(session.selectedDisplay == number)
                    }
                }
                session.selectDisplay(session.selectedDisplay + 1)
                #expect(session.selectedDisplay == 0)
            }
        }
    }

    @Test func newFieldsRoundTrip() throws {
        let host = Host(name: "A", hostname: "a", username: "u", symbol: "macmini",
                        lastConnected: Date(timeIntervalSince1970: 100))
        let back = try JSONDecoder().decode(Host.self, from: JSONEncoder().encode(host))
        #expect(back == host)
    }

    @Test func reachabilityStatesFollowProbe() async {
        let up = Host(name: "Up", hostname: "up", username: "")
        let down = Host(name: "Down", hostname: "down", username: "")
        let model = ReachabilityModel(probe: StubProbe(online: ["up"]))
        #expect(model.state(for: up) == .checking)
        let run = model.refresh([up, down])
        #expect(model.state(for: up) == .checking)
        await run.value
        #expect(model.state(for: up) == .online)
        #expect(model.state(for: down) == .offline)
    }
}

private struct StubProbe: ReachabilityProbe {
    let online: Set<String>
    func isReachable(hostname: String, port: UInt16) async -> Bool { online.contains(hostname) }
}
