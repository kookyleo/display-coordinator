import Foundation
import Network
import os

// Add logging helper function
func logAndPrint(_ message: String, level: OSLogType = .info, logger: Logger) {
    // Log to system log
    logger.log(level: level, "\(message)")
    // Print to terminal with different prefixes based on log level
    let prefix: String
    switch level {
    case .error:
        prefix = "❌"
    case .fault:
        prefix = "💥"
    case .debug:
        prefix = "🔍"
    case .info:
        prefix = "ℹ️"
    case .default:
        prefix = "🔵"
    default:
        prefix = "❓"
    }
    print(prefix + " " + message)
}

class DisplayReceiver {
    private let listenIP: String
    private let listenPort: Int
    private let expectedData: String
    private let logger = Logger(subsystem: "com.display.receiver", category: "Receiver")

    private var listener: NWListener?
    private var isRunning = true

    init(
        listenIP: String = "0.0.0.0", listenPort: Int = 12345,
        expectedData: String = "sleep_display"
    ) {
        self.listenIP = listenIP
        self.listenPort = listenPort
        self.expectedData = expectedData
    }

    func sleepDisplay() {
        do {
            try Process.run(URL(fileURLWithPath: "/usr/bin/pmset"), arguments: ["displaysleepnow"])
            logAndPrint("Display sleep signal sent successfully", logger: logger)
        } catch {
            logAndPrint("Error putting display to sleep: \(error)", level: .error, logger: logger)
        }
    }

    func stopListening() {
        isRunning = false
        listener?.cancel()
        listener = nil
        CFRunLoopStop(CFRunLoopGetCurrent())
    }

    private func handleNewConnection(_ connection: NWConnection) {
        logAndPrint("New connection from \(connection.endpoint)", logger: logger)

        // 设置接收处理
        self.setupReceive(for: connection)

        // 设置状态更新处理
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                logAndPrint("Connection failed: \(error)", level: .error, logger: self.logger)
                connection.cancel()
                // 确保监听器仍在运行
                self.ensureListenerIsRunning()
            case .ready:
                logAndPrint("Connection ready", level: .debug, logger: self.logger)
            case .cancelled:
                logAndPrint("Connection cancelled", level: .debug, logger: self.logger)
                // 确保监听器仍在运行
                self.ensureListenerIsRunning()
            default:
                logAndPrint(
                    "Connection state changed: \(state)", level: .debug, logger: self.logger)
            }
        }

        connection.start(queue: .global())
    }

    private func setupReceive(for connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) {
            [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let error = error {
                logAndPrint("Receive error: \(error)", level: .error, logger: self.logger)
                connection.cancel()
                return
            }

            if let content = content,
                let message = String(data: content, encoding: .utf8)
            {
                if message == self.expectedData {
                    logAndPrint("Received sleep_display signal", logger: self.logger)
                    self.sleepDisplay()
                } else {
                    logAndPrint(
                        "Received unexpected message: \(message)", level: .default,
                        logger: self.logger)
                }
            }

            // 如果连接仍然有效，继续接收数据
            if !isComplete {
                self.setupReceive(for: connection)
            } else {
                connection.cancel()
            }
        }
    }

    private func ensureListenerIsRunning() {
        guard isRunning else { return }

        if listener == nil {
            do {
                let parameters = NWParameters.tcp
                listener = try NWListener(
                    using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(listenPort)))
                setupListener()
                listener?.start(queue: .global())
                logAndPrint("Listener restarted successfully", logger: logger)
            } catch {
                logAndPrint("Failed to restart listener: \(error)", level: .error, logger: logger)
            }
        }
    }

    private func setupListener() {
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                logAndPrint("Listening on port \(self.listenPort)...", logger: self.logger)
            case .failed(let error):
                logAndPrint("Listener failed: \(error)", level: .error, logger: self.logger)
                self.listener = nil
                // 尝试重新启动监听器
                self.ensureListenerIsRunning()
            default:
                logAndPrint("Listener state changed: \(state)", level: .debug, logger: self.logger)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
    }

    func startListening() {
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(
                using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(listenPort)))

            setupListener()
            listener?.start(queue: .global())

            // 设置信号处理
            setupSignalHandler()

            // 修改 RunLoop 运行方式
            while isRunning {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }

            logAndPrint("Shutting down gracefully...", logger: logger)

        } catch {
            logAndPrint("Failed to create listener: \(error)", level: .error, logger: logger)
        }
    }

    private func setupSignalHandler() {
        // 设置 SIGINT 处理器
        signal(SIGINT) { _ in
            if let receiver = DisplayReceiver.shared {
                receiver.stopListening()
            }
            exit(0)
        }
    }

    static var shared: DisplayReceiver?
}

func printUsage() {
    let logger = Logger(subsystem: "com.display.receiver", category: "Usage")
    let usageText = """
        Usage: ReceiverThenSleepDisplay [options]

        Options:
          --ip <ip>        Listen IP address (default: 0.0.0.0)
          --port <port>    Listen port number (default: 12345)
          --signal <msg>   Expected signal message (default: sleep_display)
          --help          Show this help message

        Example:
          ReceiverThenSleepDisplay --port 8080 --ip 127.0.0.1
          ReceiverThenSleepDisplay --signal custom_sleep_signal
        """
    logAndPrint(usageText, logger: logger)
}

func main() {
    let logger = Logger(subsystem: "com.display.receiver", category: "Main")
    let arguments = CommandLine.arguments

    // Default values
    var listenIP = "0.0.0.0"
    var listenPort = 12345
    var expectedSignal = "sleep_display"
    var showHelp = false
    var hasArgs = false

    // Parse arguments
    var i = 1
    while i < arguments.count {
        hasArgs = true
        let arg = arguments[i]

        switch arg {
        case "--help":
            showHelp = true
            i += 1
        case "--ip":
            if i + 1 < arguments.count {
                listenIP = arguments[i + 1]
                i += 2
            } else {
                logAndPrint("Error: IP address not provided", level: .error, logger: logger)
                return
            }
        case "--port":
            if i + 1 < arguments.count {
                if let port = Int(arguments[i + 1]) {
                    if port > 0 && port < 65536 {
                        listenPort = port
                    } else {
                        logAndPrint(
                            "Error: Port must be between 1-65535", level: .error, logger: logger)
                        return
                    }
                } else {
                    logAndPrint("Error: Invalid port number", level: .error, logger: logger)
                    return
                }
                i += 2
            } else {
                logAndPrint("Error: Port number not provided", level: .error, logger: logger)
                return
            }
        case "--signal":
            if i + 1 < arguments.count {
                expectedSignal = arguments[i + 1]
                i += 2
            } else {
                logAndPrint("Error: Signal message not provided", level: .error, logger: logger)
                return
            }
        default:
            logAndPrint("Unknown argument: \(arg)", level: .error, logger: logger)
            printUsage()
            return
        }
    }

    if showHelp {
        printUsage()
        return
    }

    if !hasArgs {
        logAndPrint(
            "Note: No parameters specified, using default configuration", level: .default,
            logger: logger)
        printUsage()
        logAndPrint(
            "\n\nContinuing with default configuration...\n", level: .default, logger: logger)
    }

    let configInfo = """
        Configuration:
        Listen IP: \(listenIP)
        Listen port: \(listenPort)
        Expected signal: \(expectedSignal)
        Starting listener...
        Press Control-C to terminate the program
        """
    logAndPrint(configInfo, logger: logger)

    let receiver = DisplayReceiver(
        listenIP: listenIP, listenPort: listenPort, expectedData: expectedSignal)
    DisplayReceiver.shared = receiver  // 保存实例引用
    receiver.startListening()
}

main()
