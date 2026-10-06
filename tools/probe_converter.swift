import Foundation

@objc protocol ConverterProbeProtocol {
    func openSession(with reply: @escaping (String) -> Void)
    func closeSession(_ sessionID: String, with reply: @escaping (Bool) -> Void)
    func ping(_ message: String, with reply: @escaping (String) -> Void)
}
let service = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "org.naturalkana.inputmethod.ConverterServer"
let connection = NSXPCConnection(machServiceName: service)
connection.remoteObjectInterface = NSXPCInterface(with: ConverterProbeProtocol.self)
connection.resume()
let finished = DispatchSemaphore(value: 0)
var succeeded = false
let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    print("Service connection failed: \(error.localizedDescription)")
    finished.signal()
} as! ConverterProbeProtocol
proxy.ping("health-check") { response in
    guard response == "ConverterServer: health-check" else { finished.signal(); return }
    proxy.openSession { session in
        proxy.closeSession(session) { closed in
            succeeded = closed
            print(closed ? "Converter ping and session lifecycle passed" : "Session close failed")
            finished.signal()
        }
    }
}
if finished.wait(timeout: .now() + 15) == .timedOut { print("Converter probe timed out") }
connection.invalidate()
exit(succeeded ? 0 : 1)
