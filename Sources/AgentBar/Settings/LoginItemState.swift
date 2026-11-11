import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemState {
    private(set) var isEnabled = false
    private(set) var needsApproval = false
    private(set) var isAvailable: Bool
    @ObservationIgnored private let preview: Bool

    init(preview: Bool = false) {
        self.preview = preview
        isAvailable = !preview && Bundle.main.bundleURL.pathExtension == "app"
        refresh()
    }

    func refresh() {
        guard isAvailable else { return }
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable, !preview else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { /* The service state remains authoritative when registration fails. */ }
        refresh()
    }

    func openLoginSettings() {
        guard !preview else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
