import Darwin
import Foundation

let arguments = ProcessInfo.processInfo.arguments
guard let eventFlag = arguments.firstIndex(of: "--event"),
      arguments.indices.contains(eventFlag + 1),
      let event = CodexHookEvent(rawValue: arguments[eventFlag + 1]) else {
    finish(includeNeutralJSON: false)
}

let deadline = DispatchTime.now().uptimeNanoseconds + 250_000_000
do {
    let input = try readStandardInput(deadline: deadline)
    if DispatchTime.now().uptimeNanoseconds < deadline {
        let remaining = Double(deadline - DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        _ = BridgeProcessor.forward(input, expectedEvent: event, socketPath: socketPath, timeout: remaining, now: Date())
    }
} catch {
    // The bridge never writes provider data or diagnostics back into Codex.
}
finish(includeNeutralJSON: event == .stop)

var socketPath: String {
    #if DEBUG
    if let testPath = ProcessInfo.processInfo.environment["NUDGE_TEST_SOCKET_PATH"], testPath.hasPrefix("/tmp/") {
        return testPath
    }
    #endif
    return BridgeProcessor.socketPath
}

func finish(includeNeutralJSON: Bool) -> Never {
    // Stop requires JSON on stdout; other hooks can safely complete with no output.
    if includeNeutralJSON { FileHandle.standardOutput.write(Data("{}\n".utf8)) }
    exit(EXIT_SUCCESS)
}

func readStandardInput(deadline: UInt64) throws -> Data {
    let flags = fcntl(STDIN_FILENO, F_GETFL)
    guard flags >= 0, fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) == 0 else { throw WireError.unavailable }
    var input = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while true {
        let result = buffer.withUnsafeMutableBytes { raw in
            Darwin.read(STDIN_FILENO, raw.baseAddress, raw.count)
        }
        if result > 0 {
            guard input.count + result <= 1_048_576 else { throw HookPayloadError.inputTooLarge }
            input.append(contentsOf: buffer.prefix(result))
            continue
        }
        if result == 0 { return input }
        if errno == EINTR { continue }
        if errno == EAGAIN || errno == EWOULDBLOCK {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw WireError.timedOut }
            let milliseconds = Int32(max(1, min((deadline - now + 999_999) / 1_000_000, 250)))
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, milliseconds)
            if ready > 0 { continue }
            if ready == 0 { throw WireError.timedOut }
            if errno != EINTR { throw WireError.unavailable }
            continue
        }
        throw WireError.unavailable
    }
}
