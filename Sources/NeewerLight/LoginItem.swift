//  LoginItem.swift — "Open at login" via SMAppService (macOS 13+).
//
//  The system owns the truth here: the user can also flip it in System Settings ›
//  General › Login Items, so we re-read the status rather than caching a preference.

import Foundation
import ServiceManagement

final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var error: String?

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func set(_ on: Bool) {
        error = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // NL-LOGIN-01: the system refused to add/remove the login item.
            self.error = "NL-LOGIN-01 · Couldn't \(on ? "enable" : "disable") open at login: \(error.localizedDescription)"
        }
        refresh()
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
