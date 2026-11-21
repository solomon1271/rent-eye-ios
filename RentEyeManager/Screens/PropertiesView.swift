import SwiftUI

struct PropertiesView: View {
    @Environment(AppState.self) private var app
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                if store.properties.isEmpty && !store.isLoading {
                    EmptyStateView(
                        title: "No buildings yet",
                        message: "Add buildings on the website or import your rent register there.",
                        systemImage: "building.2"
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(store.properties) { property in
                    NavigationLink(value: property) {
                        PropertyRow(property: property, units: store.units.filter { $0.propertyId == property.id })
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Properties")
            .navigationDestination(for: Property.self) { PropertyDetailView(property: $0) }
            .refreshable { await store.load(using: app) }
            .task { await store.loadIfNeeded(using: app) }
            .overlay { if store.isLoading && store.properties.isEmpty { ProgressView() } }
        }
    }
}

private struct PropertyRow: View {
    let property: Property
    let units: [PropertyUnit]

    var body: some View {
        let occupied = units.filter { $0.status == "Occupied" }.count
        let share = units.isEmpty ? 0 : Double(occupied) / Double(units.count)
        VStack(alignment: .leading, spacing: 6) {
            Text(property.name).font(.headline).foregroundStyle(Theme.ink)
            Text(property.area.isEmpty ? property.propertyType : "\(property.area) · \(property.propertyType)")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                ProgressView(value: share).tint(Theme.brand)
                Text("\(occupied)/\(units.count) let").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
    }
}

struct PropertyDetailView: View {
    let property: Property
    @Environment(PortfolioStore.self) private var store

    struct FloorGroup: Identifiable {
        let name: String
        let units: [PropertyUnit]
        var id: String { name }
    }

    /// Units grouped by floor ("G", "1", "2"…), unnamed floors last.
    private var floors: [FloorGroup] {
        let units = store.units.filter { $0.propertyId == property.id }
        let grouped = Dictionary(grouping: units) { ($0.floor ?? "").trimmingCharacters(in: .whitespaces) }
        return grouped.keys
            .sorted { lhs, rhs in
                if lhs.isEmpty != rhs.isEmpty { return !lhs.isEmpty }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .map { key in
                FloorGroup(
                    name: key.isEmpty ? "No floor set" : "Floor \(key)",
                    units: (grouped[key] ?? []).sorted { $0.unit.localizedStandardCompare($1.unit) == .orderedAscending }
                )
            }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Address", value: property.address.isEmpty ? "—" : property.address)
                LabeledContent("Area", value: property.area.isEmpty ? "—" : property.area)
                LabeledContent("Occupancy", value: property.occupancyRate)
            }
            ForEach(floors) { floor in
                Section(floor.name) {
                    ForEach(floor.units) { unit in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(unit.unit).font(.subheadline.weight(.semibold))
                                Text(unit.status == "Occupied" ? unit.tenant : "Vacant")
                                    .font(.caption)
                                    .foregroundStyle(unit.status == "Occupied" ? Theme.ink : Theme.muted)
                            }
                            Spacer()
                            Text(Money.etb(unit.monthlyRent)).font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }
        .screenBackground()
        .navigationTitle(property.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
