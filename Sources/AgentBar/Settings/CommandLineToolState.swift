import Foundation
import Observation

/// The `agentbar` command as the settings show it.
@MainActor
@Observable
final class CommandLineToolState {
    private(set) var isInstalled = false
    private(set) var isChanging = false
    /// Why the last change did not happen.
    private(set) var problem: String?
    @ObservationIgnored private let tool: CommandLineTool?

    /// `tool` is nil where the app does not install the command: outside an app bundle, and in previews.
    init(tool: CommandLineTool?) {
        self.tool = tool
        refresh()
    }

    var isAvailable: Bool { tool != nil }

    func refresh() {
        guard let tool, !isChanging else { return }
        isInstalled = tool.isInstalled
    }

    func setInstalled(_ installed: Bool) {
        guard let tool, !isChanging else { return }
        isChanging = true
        problem = nil
        Task {
            // Off the main actor: the system may ask for a password first, for as long as that takes.
            let failure = await Task.detached { () -> CommandLineTool.Failure? in
                do throws(CommandLineTool.Failure) {
                    if installed { try tool.install() } else { try tool.uninstall() }
                    return nil
                } catch {
                    return error
                }
            }.value
            isChanging = false
            refresh()
            problem = switch failure {
            case .taken: "Another program is already installed as “agentbar”."
            case .failed: "Couldn’t \(installed ? "install" : "remove") the “agentbar” terminal command."
            case nil: nil
            }
        }
    }
}
