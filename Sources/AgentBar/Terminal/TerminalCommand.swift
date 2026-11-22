import AgentBarCore
import Foundation

/// A launch with `--terminal`: prints the accounts and exits, in place of starting the app. It is what
/// the `agentbar` command runs.
struct TerminalCommand: Equatable {
    struct UnknownOption: Error, Equatable {
        let option: String
    }

    static let flag = "--terminal"
    static let usage = "Usage: agentbar [claude] [codex] [name ...] [--all] [--no-color]"
    static let help = """
        \(usage)

        Shows the usage, sessions, and tokens of the Claude Code and Codex accounts
        on this Mac, in the order arranged in AgentBar's settings.

          claude, codex   Only the accounts of that provider
          name            Only the accounts whose name contains it
          -a, --all       Include the accounts hidden in the settings
              --no-color  Plain text
          -h, --help      Show this help
        """

    var providers: Set<ProviderKind> = []
    var names: [String] = []
    var includesHidden = false
    var allowsColors = true
    var demo = false
    var showsHelp = false

    /// `arguments` are the words after the program's name.
    init(arguments: [String]) throws(UnknownOption) {
        for argument in arguments {
            switch argument {
            case Self.flag: break
            case "--demo": demo = true
            case "-a", "--all": includesHidden = true
            case "--no-color": allowsColors = false
            case "-h", "--help": showsHelp = true
            default:
                if argument.hasPrefix("-") { throw UnknownOption(option: argument) }
                if let provider = ProviderKind(rawValue: argument.lowercased()) {
                    providers.insert(provider)
                } else {
                    names.append(argument)
                }
            }
        }
    }

    func selects(_ account: Account) -> Bool {
        (providers.isEmpty || providers.contains(account.id.provider))
            && (names.isEmpty || names.contains { account.name.localizedCaseInsensitiveContains($0) })
    }

    /// Runs the command line and returns its exit status.
    @MainActor
    static func run(_ arguments: [String]) async -> Int32 {
        let command: TerminalCommand
        do {
            command = try TerminalCommand(arguments: arguments)
        } catch {
            write("agentbar: unknown option \(error.option)\n\(usage)\n", to: .standardError)
            return 2
        }
        if command.showsHelp {
            write(help + "\n", to: .standardOutput)
            return EXIT_SUCCESS
        }
        let providers = ProviderComposition.make(demo: command.demo)
        let settings = AppSettings()
        let found = await TerminalAccounts.discover(providers).map { AccountState(account: $0) }
        let listed = command.includesHidden
            ? MenuBarAccounts.ordered(found, settings: settings) : MenuBarAccounts.visible(found, settings: settings)
        let accounts = listed.map(\.account).filter(command.selects)
        guard !accounts.isEmpty else {
            let selective = !command.providers.isEmpty || !command.names.isEmpty
            write((found.isEmpty ? "No accounts found" : selective ? "No accounts match" : "No visible accounts") + "\n",
                  to: .standardError)
            return EXIT_FAILURE
        }
        let states = await TerminalAccounts.load(accounts, from: providers)
        let dashboard = TerminalDashboard(accounts: states, now: Date())
        write(dashboard.text(width: terminalWidth, colors: command.allowsColors && terminalShowsColors) + "\n",
              to: .standardOutput)
        return EXIT_SUCCESS
    }

    private static func write(_ text: String, to handle: FileHandle) {
        handle.write(Data(text.utf8))
    }

    /// The width asked for with `COLUMNS`, else that of the terminal the output goes to.
    private static var terminalWidth: Int {
        if let columns = ProcessInfo.processInfo.environment["COLUMNS"].flatMap({ Int($0) }), columns > 0 {
            return columns
        }
        var size = winsize()
        // TIOCGWINSZ, a macro Swift does not import.
        if ioctl(STDOUT_FILENO, 0x4008_7468, &size) == 0, size.ws_col > 0 { return Int(size.ws_col) }
        return 80
    }

    private static var terminalShowsColors: Bool {
        let environment = ProcessInfo.processInfo.environment
        return isatty(STDOUT_FILENO) == 1 && environment["NO_COLOR", default: ""].isEmpty && environment["TERM"] != "dumb"
    }
}
