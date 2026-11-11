@testable import ClaudeProvider
import Foundation
import Testing

struct HistoryTests {
    @Test func containmentChecksResolvedPathsAndDirectoryBoundaries() throws {
        let space = try TestSpace()
        let account = try space.account()
        let root = account.home.appendingPathComponent("sessions")
        let own = root.appendingPathComponent("nested/101.json")
        let outside = account.home.appendingPathComponent("sessions-other/101.json")
        try space.write(["synthetic": true], to: own)
        try space.write(["synthetic": true], to: outside)
        let internalLink = root.appendingPathComponent("101.json")
        let externalLink = root.appendingPathComponent("102.json")
        try FileManager.default.createSymbolicLink(at: internalLink, withDestinationURL: own)
        try FileManager.default.createSymbolicLink(at: externalLink, withDestinationURL: outside)
        let history = try #require(HistoryDirectory(home: account.home, component: "sessions"))
        #expect(history.resolve(internalLink) == own.resolvingSymlinksInPath())
        #expect(history.resolve(externalLink) == nil)
        #expect(history.resolve(outside) == nil)
        let alias = space.root.appendingPathComponent(".claude-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: account.home)
        #expect(HistoryDirectory(home: alias, component: "sessions") == nil)
    }
}
