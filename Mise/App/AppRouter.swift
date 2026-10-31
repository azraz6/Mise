import Foundation
import Observation
import SwiftUI

enum PaywallReason: String, Identifiable {
    case importLimit
    case collectionLimit
    case general

    var id: String { rawValue }
}

struct AppToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var symbol: String = "checkmark.circle.fill"
}

@MainActor
@Observable
final class AppRouter {
    enum Tab: String, Hashable {
        case home
        case library
        case shopping
        case plan
    }

    var selectedTab: Tab = .home
    var showImport = false
    var showSettings = false
    var paywallReason: PaywallReason?
    var toast: AppToast?

    private var toastTask: Task<Void, Never>?

    func openImport() {
        showImport = true
    }

    func showToast(_ message: String, symbol: String = "checkmark.circle.fill") {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            toast = AppToast(message: message, symbol: symbol)
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self?.toast = nil
            }
        }
    }
}
