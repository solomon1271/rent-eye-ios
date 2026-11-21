import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(PortfolioStore.self) private var store
    @AppStorage("calendar") private var calendarRaw = CalendarSystem.gregorian.rawValue
    @State private var report: PeriodReport?
    @State private var showSettings = false

    private var calendar: CalendarSystem { CalendarSystem(rawValue: calendarRaw) ?? .gregorian }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let message = store.errorMessage {
                        Text(message).font(.callout).foregroundStyle(Theme.danger)
                    }

                    if !store.pendingPayments.isEmpty {
                        reviewCallout
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(
                            label: "Occupancy",
                            value: store.units.isEmpty ? "—" : "\(Int((Double(store.occupiedUnits) / Double(store.units.count) * 100).rounded()))%",
                            note: "\(store.occupiedUnits) of \(store.units.count) units"
                        )
                        MetricCard(
                            label: "Collected",
                            value: report.map { Money.etb($0.totalCollected) } ?? "—",
                            note: monthName
                        )
                        MetricCard(
                            label: "Outstanding",
                            value: Money.etb(store.openInvoices.reduce(0) { $0 + $1.balanceDue }),
                            note: "\(store.openInvoices.count) open invoices"
                        )
                        MetricCard(
                            label: "Overdue",
                            value: "\(store.invoices.filter { $0.status == "Overdue" }.count)",
                            note: "invoices past due"
                        )
                    }

                    overdueList
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Home")
            .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoiceId: $0.id) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .refreshable { await refresh() }
            .task { await store.loadIfNeeded(using: app); await loadReport() }
            .onChange(of: calendarRaw) { _, _ in Task { await loadReport() } }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(app.session?.workspaceName ?? "")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Signed in as \(app.session?.fullName ?? "") · \(app.session?.roleLabel ?? "")")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
            TibebBand(height: 6).clipShape(Capsule())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.brandDeep, in: RoundedRectangle(cornerRadius: 16))
    }

    private var reviewCallout: some View {
        let count = store.pendingPayments.count
        return HStack(spacing: 12) {
            Text("\(count)")
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(Theme.brand, in: Circle())
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "Payment waiting for review" : "Payments waiting for review")
                    .font(.subheadline.weight(.semibold))
                Text("\(Money.etb(store.pendingPayments.reduce(0) { $0 + $1.amount })) sent by tenants. Open the Payments tab.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var overdueList: some View {
        let overdue = store.invoices.filter { $0.status == "Overdue" }.sorted { $0.dueDate < $1.dueDate }.prefix(6)
        if !overdue.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Overdue").font(.headline).foregroundStyle(Theme.ink)
                ForEach(Array(overdue)) { invoice in
                    NavigationLink(value: invoice) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invoice.tenant).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                Text("\(invoice.propertyName) · \(invoice.unit)").font(.caption).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Money.etb(invoice.balanceDue)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.danger)
                                DateLabel(iso: invoice.dueDate).font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    /// This month in the chosen calendar.
    private var monthRange: (from: String, to: String, label: String) {
        let today = AppDate.parts(AppDate.todayISO())!
        if calendar == .ethiopian {
            let ec = EthiopianCalendar.fromGregorian(year: today.year, month: today.month, day: today.day)
            let lastDay = ec.month < 13 ? 30 : (ec.year % 4 == 3 ? 6 : 5)
            let start = EthiopianCalendar.toGregorian(year: ec.year, month: ec.month, day: 1)
            let end = EthiopianCalendar.toGregorian(year: ec.year, month: ec.month, day: lastDay)
            return (iso(start), iso(end), "\(EthiopianCalendar.monthNames[ec.month - 1]) \(ec.year) E.C.")
        }
        let days = Calendar(identifier: .gregorian).range(of: .day, in: .month, for: Date())?.count ?? 30
        let names = DateFormatter().monthSymbols ?? []
        return (
            String(format: "%04ld-%02ld-01", today.year, today.month),
            String(format: "%04ld-%02ld-%02ld", today.year, today.month, days),
            names.isEmpty ? "This month" : "\(names[today.month - 1]) \(today.year)"
        )
    }

    private var monthName: String { "this month · \(monthRange.label)" }

    private func iso(_ parts: (year: Int, month: Int, day: Int)) -> String {
        String(format: "%04ld-%02ld-%02ld", parts.year, parts.month, parts.day)
    }

    private func loadReport() async {
        let range = monthRange
        report = try? await app.api.periodReport(from: range.from, to: range.to)
    }

    private func refresh() async {
        await store.load(using: app)
        await loadReport()
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("calendar") private var calendar = CalendarSystem.gregorian.rawValue
    @State private var serverAddress = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Dates") {
                    Picker("Calendar", selection: $calendar) {
                        ForEach(CalendarSystem.allCases) { system in
                            Text(system == .gregorian ? "Gregorian (G.C.)" : "Ethiopian (E.C.)").tag(system.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Account") {
                    LabeledContent("Name", value: app.session?.fullName ?? "")
                    LabeledContent("Email", value: app.session?.email ?? "")
                    LabeledContent("Organisation", value: app.session?.workspaceName ?? "")
                    LabeledContent("Role", value: app.session?.roleLabel ?? "")
                }

                Section {
                    TextField("Server address", text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server")
                } footer: {
                    Text("Changing the server signs you out.")
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task {
                            await app.signOut()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if serverAddress != app.serverAddress {
                            app.setServerAddress(serverAddress)
                            app.signOutLocally()
                        }
                        dismiss()
                    }
                }
            }
            .onAppear { serverAddress = app.serverAddress }
        }
    }
}
