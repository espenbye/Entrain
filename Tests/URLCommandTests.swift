import Foundation
import Testing
@testable import Entrain

struct URLCommandTests {
    private func parse(_ s: String) -> URLCommand? { URLCommand(URL(string: s)!) }

    @Test func parsesCommands() {
        #expect(parse("entrain://play?mode=focus&length=30") == .play(mode: .focus, length: .thirty))
        #expect(parse("entrain://play") == .play(mode: nil, length: nil))
        #expect(parse("entrain://play?mode=deepSleep") == .play(mode: .deepSleep, length: nil))
        #expect(parse("entrain://pause") == .pause)
        #expect(parse("entrain://toggle") == .toggle)
    }

    @Test func rejectsBadInput() {
        #expect(parse("entrain://play?mode=jazz") == nil)
        #expect(parse("entrain://play?length=7") == nil)
        #expect(parse("entrain://dance") == nil)
        #expect(parse("other://play") == nil)
    }
}
