import SwiftUI

struct RootView: View {
    @Environment(AppDependencies.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()
    @State private var showStartupWarning = false

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            HomeView()
                .tag(AppRouter.Tab.home)
                .tabItem { Label("Home", systemImage: "house") }

            LibraryView()
                .tag(AppRouter.Tab.library)
                .tabItem { Label("Library", systemImage: "books.vertical") }

            ShoppingView()
                .tag(AppRouter.Tab.shopping)
                .tabItem { Label("Shopping", systemImage: "cart") }

            MealPlanView()
                .tag(AppRouter.Tab.plan)
                .tabItem { Label("Meal Plan", systemImage: "calendar") }
        }
        .environment(router)
        .tint(MiseTheme.accent)
        .sheet(isPresented: $router.showImport) {
            ImportView()
                .environment(router)
                .environment(app)
                .modelContainer(app.container)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
                .environment(router)
                .environment(app)
                .modelContainer(app.container)
        }
        .sheet(item: $router.paywallReason) { reason in
            PaywallView(reason: reason)
                .environment(router)
                .environment(app)
                .modelContainer(app.container)
        }
        .overlay(alignment: .bottom) {
            if let toast = router.toast {
                ToastView(toast: toast)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 72)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .task {
            await app.start()
            let count = await app.consumeSharedImports()
            if app.sharedImportLimitReached {
                router.paywallReason = .importLimit
            } else if count > 0 {
                router.showToast(count == 1 ? "Shared item added to Mise" : "\(count) shared items added to Mise")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                let count = await app.consumeSharedImports()
                if app.sharedImportLimitReached {
                    router.paywallReason = .importLimit
                } else if count > 0 {
                    router.showImport = true
                    router.showToast(count == 1 ? "Ready to review your shared item" : "Ready to review \(count) shared items")
                }
            }
        }
        .onOpenURL { url in
            app.handleDeepLink(url)
            router.showImport = true
        }
        .onAppear {
            if app.startupWarning != nil {
                showStartupWarning = true
            }
        }
        .alert("Temporary library", isPresented: $showStartupWarning) {
            Button("Continue", role: .cancel) {}
        } message: {
            Text(app.startupWarning ?? "")
        }
    }
}

struct ToastView: View {
    let toast: AppToast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .foregroundStyle(MiseTheme.positive)
                .accessibilityHidden(true)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(MiseTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            Capsule(style: .continuous)
                .fill(MiseTheme.surface)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 7)
        )
        .overlay(Capsule().stroke(MiseTheme.line, lineWidth: 1))
    }
}
