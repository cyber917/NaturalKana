import Foundation

// Offline integration probe: sends only fixed test keystrokes to a private
// converter session. No host application text or provider credentials are read.
@objc protocol TypingProbeProtocol {
    func handleCommand(_ data: Data, with reply: @escaping (Data?, NSString?) -> Void)
    func closeSession(_ sessionID: String, with reply: @escaping (Bool) -> Void)
}
let connection = NSXPCConnection(machServiceName: "org.naturalkana.inputmethod.ConverterServer")
connection.remoteObjectInterface = NSXPCInterface(with: TypingProbeProtocol.self)
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    fputs("XPC failure: \(error.localizedDescription)\n", stderr)
    exit(1)
} as! TypingProbeProtocol
func send(_ command: [String: Any]) throws -> [String: Any] {
    let done = DispatchSemaphore(value: 0)
    var result: Data?
    var failure: NSString?
    proxy.handleCommand(try JSONSerialization.data(withJSONObject: command)) { data, error in
        result = data; failure = error; done.signal()
    }
    guard done.wait(timeout: .now() + 20) == .success, let result else {
        throw NSError(domain: "TypingProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: failure as String? ?? "Timed out"])
    }
    return try JSONSerialization.jsonObject(with: result) as! [String: Any]
}
func require(_ ok: Bool, _ message: String) throws {
    if !ok { throw NSError(domain: "TypingProbe", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
}
do {
    for live in [false, true] {
        let session = "offline-typing-probe-" + UUID().uuidString
        defer {
            let closed = DispatchSemaphore(value: 0)
            proxy.closeSession(session) { _ in closed.signal() }
            _ = closed.wait(timeout: .now() + 5)
        }
        let keys: [(String, Int)] = [("n",45),("i",34),("h",4),("o",31),("n",45),("g",5),("o",31),(" ",49),("\r",36)]
        var committed = ""
        for (index, key) in keys.enumerated() {
            var request: [String: Any] = [
                "eventID": index + 1,
                "event": ["modifierFlags": 0, "characters": key.0, "charactersIgnoringModifiers": key.0, "keyCode": key.1],
                "inputStyle": ["defaultRomanToKana": [:]], "liveConversionEnabled": live,
                "enableDebugWindow": false, "enableSuggestion": false,
                "enablePredictiveTyping": false, "enableTypoCorrection": false,
                "enableOptionDirectFullWidthInput": false, "typeBackSlash": false,
                "context": [:], "visibleCandidateStartIndex": 0
            ]
            if index == 0 {
                request["activation"] = ["inputLanguage": ["japanese": [:]], "config": [
                    "aiBackendPreference": "Off", "openAIModelName": "", "openAIEndpoint": "",
                    "openAIAPIKey": ["value": ""], "includeContextInAITransform": false
                ]]
            }
            let response = try send([index == 0 ? "openSession" : "session": [
                "sessionID": session, "command": ["handleKeyEvent": ["_0": request]]
            ]])
            try require(response["handled"] as? Bool == true, "Key \(index) was not handled")
            if index == 6 {
                let snapshot = response["snapshot"] as? [String: Any] ?? [:]
                try require(snapshot["convertTarget"] as? String == "にほんご", "Romaji did not produce にほんご: \(snapshot["convertTarget"] ?? "missing")")
            }
            for effect in response["effects"] as? [[String: Any]] ?? [] {
                if let insertion = effect["insertText"] as? [String: Any], let text = insertion["_0"] as? String { committed += text }
            }
        }
        try require(committed == "日本語", "Expected 日本語, received \(committed)")
        print("PASS liveConversion=\(live): nihongo → にほんご → 日本語; Space + Return committed text")
    }
    connection.invalidate()
} catch {
    fputs("FAIL: \(error.localizedDescription)\n", stderr)
    connection.invalidate()
    exit(1)
}
