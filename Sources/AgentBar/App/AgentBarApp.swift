import AppKit

@main
@MainActor
enum AgentBarApp {
    static func main() {
        let options: LaunchOptions
        do {
            options = try LaunchOptions(arguments: CommandLine.arguments)
        } catch {
            FileHandle.standardError.write(Data("Usage: AgentBar [--demo] [--log] [--snapshot <directory>]\n".utf8))
            exit(EXIT_FAILURE)
        }
        let application = NSApplication.shared
        let delegate = AppDelegate(options: options)
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
