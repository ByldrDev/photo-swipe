import SwiftUI
import Photos

/// Lets the user pick where in the library the session should begin.
struct StartPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void

    @State private var jumpDate = Date()
    @State private var scrollTarget: String?

    private struct MonthGroup: Identifiable {
        let id: String
        let title: String
        let ids: [String]
    }

    private var groups: [MonthGroup] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        var result: [MonthGroup] = []
        var currentKey = ""
        for id in model.library.assetIDs {
            let date = model.library.asset(for: id)?.creationDate ?? .distantPast
            let comps = calendar.dateComponents([.year, .month], from: date)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if key != currentKey {
                currentKey = key
                result.append(MonthGroup(id: key, title: formatter.string(from: date), ids: []))
            }
            result[result.count - 1] = MonthGroup(id: key, title: result[result.count - 1].title,
                                                  ids: result[result.count - 1].ids + [id])
        }
        return result
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: .sectionHeaders) {
                    ForEach(groups) { group in
                        Section {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(group.ids, id: \.self) { id in
                                    Button {
                                        onPick(id)
                                        dismiss()
                                    } label: {
                                        GeometryReader { geo in
                                            AssetThumbnail(assetID: id, side: geo.size.width)
                                        }
                                        .aspectRatio(1, contentMode: .fit)
                                    }
                                    .id(id)
                                    .accessibilityIdentifier("startTile")
                                }
                            }
                        } header: {
                            Text(group.title)
                                .font(.headline)
                                .padding(.horizontal).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.bar)
                        }
                    }
                }
            }
            .onChange(of: scrollTarget) { _, target in
                if let target { withAnimation { proxy.scrollTo(target, anchor: .top) } }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("Jump to")
                DatePicker("Jump to", selection: $jumpDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: jumpDate) { _, date in scrollTarget = firstAssetID(onOrBefore: date) }
            }
            .font(.subheadline)
            .padding(.horizontal).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
        .navigationTitle("Start from…")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    /// Newest asset created on or before the end of `date`'s day.
    private func firstAssetID(onOrBefore date: Date) -> String? {
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
        return model.library.assetIDs.first { id in
            (model.library.asset(for: id)?.creationDate ?? .distantPast) < endOfDay
        }
    }
}
