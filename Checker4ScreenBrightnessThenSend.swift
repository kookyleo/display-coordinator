import Foundation
import IOKit
import IOKit.pwr_mgt
import Network
import os

// Add a helper function to log and print messages
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

class ScreenBrightnessChecker {
    private var lastState: Bool?
    private var timer: Timer?
    private let targetHost: String
    private let targetPort: Int
    private let targetContent: String
    private let logger = Logger(subsystem: "com.screenbrightness.checker", category: "Monitor")
    private var isRunning = true  // 添加运行状态标志

    static var shared: ScreenBrightnessChecker!

    init(host: String, port: Int, content: String) {
        self.targetHost = host
        self.targetPort = port
        self.targetContent = content
    }

    deinit {
        stopMonitoring()
    }

    func stopMonitoring() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        CFRunLoopStop(CFRunLoopGetCurrent())
    }

    private func sendSleepSignal() {
        let connection = NWConnection(
            host: NWEndpoint.Host(targetHost),
            port: NWEndpoint.Port(integerLiteral: UInt16(targetPort)),
            using: .tcp)

        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                connection.send(
                    content: self.targetContent.data(using: .utf8),
                    completion: .contentProcessed { [self] error in
                        if let error = error {
                            logAndPrint(
                                "Failed to send signal: \(error.localizedDescription)",
                                level: .error, logger: logger)
                        } else {
                            logAndPrint("Signal sent: \(self.targetContent)", logger: logger)
                        }
                        connection.cancel()
                    })
            case .setup:
                logAndPrint("Setting up connection...", level: .debug, logger: logger)
            case .failed(let error):
                logAndPrint(
                    "Connection failed: \(error.localizedDescription)", level: .error,
                    logger: logger)
                connection.cancel()
            case .cancelled:
                logAndPrint("Connection cancelled", level: .debug, logger: logger)
            case .preparing:
                logAndPrint("Preparing connection...", level: .debug, logger: logger)
            case .waiting(let error):
                logAndPrint(
                    "Waiting for connection: \(error.localizedDescription)", level: .default,
                    logger: logger)
            default:
                logAndPrint("Unknown connection state", level: .error, logger: logger)
                connection.cancel()
            }
        }

        connection.start(queue: .global())
    }

    private func setupSignalHandler() {
        signal(SIGINT) { _ in
            if let checker = ScreenBrightnessChecker.shared {
                checker.stopMonitoring()
            }
            exit(0)
        }
    }

    func startMonitoring() {
        // Check screen state every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkDisplayState()
        }

        // 设置信号处理
        setupSignalHandler()

        // 修改 RunLoop 运行方式
        while isRunning {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }

        logAndPrint("Shutting down gracefully...", logger: logger)
    }

    private func checkDisplayState() {
        let currentState = Self.isDisplayOn()

        if lastState != currentState {
            logAndPrint("Display state changed: \(currentState ? "On" : "Off")", logger: logger)

            if currentState {
                logAndPrint("Sending device on signal", logger: logger)
                sendSleepSignal()
            }

            lastState = currentState
        }
    }

    static func isDisplayOn() -> Bool {
        var iterator: io_iterator_t = 0

        let result = IOServiceGetMatchingServices(
            kIOMasterPortDefault,
            IOServiceMatching("IODisplayWrangler"),
            &iterator)

        guard result == KERN_SUCCESS else {
            Logger(subsystem: "com.screenbrightness.checker", category: "Monitor")
                .error("Error: Unable to get display services")
            return false
        }

        defer {
            IOObjectRelease(iterator)
        }

        let service = IOIteratorNext(iterator)
        defer {
            IOObjectRelease(service)
        }

        var properties: Unmanaged<CFMutableDictionary>?

        let kernResult = IORegistryEntryCreateCFProperties(
            service,
            &properties,
            kCFAllocatorDefault,
            0)

        guard kernResult == KERN_SUCCESS,
            let cfDict = properties?.takeRetainedValue(),
            let dict = cfDict as NSDictionary as? [String: Any]
        else {
            Logger(subsystem: "com.screenbrightness.checker", category: "Monitor")
                .error("Error: Unable to get display properties")
            return false
        }

        if let displayOnline = dict["IOPowerManagement"] as? [String: Any],
            let displayState = displayOnline["CurrentPowerState"] as? Int
        {
            return displayState != 1
        }

        return false
    }
}

func printUsage() {
    let logger = Logger(subsystem: "com.screenbrightness.checker", category: "Usage")
    let usageText = """
        Usage: ScreenBrightnessCheckerAndSender [options]

        Options:
          --host <ip>      Target host IP address (default: 127.0.0.1)
          --port <port>    Target port number (default: 12345)
          --content <msg>  Message content to send (default: sleep_display)
          --help           Show this help message

        Example:
          ScreenBrightnessCheckerAndSender --host 192.168.1.100 --port 8080
          ScreenBrightnessCheckerAndSender --content custom_message
        """
    logAndPrint(usageText, logger: logger)
}

func main() {
    let logger = Logger(subsystem: "com.screenbrightness.checker", category: "Main")
    // Parse command line arguments
    let arguments = CommandLine.arguments

    // Set default values
    var host = "127.0.0.1"
    var port = 12345
    var content = "sleep_display"
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
        case "--host":
            if i + 1 < arguments.count {
                host = arguments[i + 1]
                i += 2
            } else {
                logAndPrint("Error: Missing value for --host", level: .error, logger: logger)
                return
            }
        case "--port":
            if i + 1 < arguments.count, let p = Int(arguments[i + 1]) {
                if p > 0 && p < 65536 {
                    port = p
                    i += 2
                } else {
                    logAndPrint("Error: Port number \(p) must be between 1-65535", level: .error, logger: logger)
                    return
                }
            } else {
                logAndPrint("Error: Invalid or missing port number", level: .error, logger: logger)
                return
            }
        case "--content":
            if i + 1 < arguments.count {
                content = arguments[i + 1]
                i += 2
            } else {
                logAndPrint("Error: Missing value for --content", level: .error, logger: logger)
                return
            }
        default:
            logAndPrint("Warning: Unrecognized argument: \(arg)", level: .error, logger: logger)
            i += 1
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
        Target host: \(host)
        Target port: \(port)
        Message content: \(content)
        Starting to monitor display state...
        Press Control-C to terminate the program\n
        """
    logAndPrint(configInfo, logger: logger)

    // Create instance and save reference
    ScreenBrightnessChecker.shared = ScreenBrightnessChecker(
        host: host, port: port, content: content)

    // Start monitoring
    ScreenBrightnessChecker.shared.startMonitoring()
}

main()
