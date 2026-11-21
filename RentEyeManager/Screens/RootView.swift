import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var store = PortfolioStore()
    @State private var tenantStore = TenantStore()

    var body: some View {
        Group {
            if app.session == nil {
                SignInView()
            } else if app.session?.isPlatform == true {
                PlatformHomeView()
            } else if app.session?.isTenant == true {
                TenantTabView()
                    .environment(tenantStore)
            } else {
                MainTabView()
                    .environment(store)
            }
        }
        .tint(Theme.brand)
        .task { await app.validateSession() }
        .onChange(of: app.session?.userId) { _, _ in
            store.reset()
            tenantStore.reset()
        }
    }
}

struct MainTabView: View {
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            PropertiesView()
                .tabItem { Label("Properties", systemImage: "building.2") }
            LeasesView()
                .tabItem { Label("Leases", systemImage: "doc.text") }
            InvoicesView()
                .tabItem { Label("Invoices", systemImage: "list.bullet.rectangle") }
            PaymentsView()
                .tabItem { Label("Payments", systemImage: "banknote") }
                .badge(store.pendingPayments.count)
        }
    }
}

/// Small helper: a date in the viewer's chosen calendar.
struct DateLabel: View {
    let iso: String?
    @AppStorage("calendar") private var calendar = CalendarSystem.gregorian.rawValue

    var body: some View {
        Text(AppDate.format(iso, calendar: CalendarSystem(rawValue: calendar) ?? .gregorian))
    }
}

/// Shown when a list is empty or failed to load.
struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage = "tray"

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

/// Header shared by the tabs: organisation name over the tibeb band.
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}
