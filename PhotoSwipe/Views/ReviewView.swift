import SwiftUI

/// Shows everything queued for deletion or hiding. Tap a tile to rescue it.
struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showResult = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        Group {
            if let session = model.session, session.pendingCount > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        section(title: "To delete", ids: session.deleteIDs, verdict: .delete)
                        section(title: "To hide", ids: session.hideIDs, verdict: .hide)
                        Text("Tap a photo to rescue it. iOS will ask you to confirm once for hiding and once for deleting. Deleted photos go to Recently Deleted for 30 days; hidden photos move to the Face ID-locked Hidden album.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
                .safeAreaInset(edge: .bottom) {
                    commitButton(session: session)
                }
            } else {
                ContentUnavailableView("Nothing queued", systemImage: "checkmark.circle",
                                       description: Text("Swipe left to queue deletions or up to queue hides."))
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }.accessibilityIdentifier("reviewDoneButton")
            }
        }
        .alert("Couldn't apply changes", isPresented: Binding(
            get: { model.commitError != nil },
            set: { if !$0 { model.commitError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.commitError ?? "")
        }
        .alert("Done", isPresented: $showResult) {
            Button("OK") { dismiss() }
        } message: {
            if let r = model.lastCommit {
                Text("Deleted \(r.deletedCount.formatted()) and hid \(r.hiddenCount.formatted()).")
            }
        }
    }

    @ViewBuilder
    private func section(title: String, ids: [String], verdict: SwipeDecision) -> some View {
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(title) · \(ids.count.formatted())", systemImage: verdict.systemImage)
                    .font(.headline)
                    .foregroundStyle(verdict.color)
                    .padding(.horizontal)
                    .accessibilityIdentifier("\(verdict.rawValue)SectionHeader")
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(ids, id: \.self) { id in
                        Button {
                            Haptics.light()
                            withAnimation { model.rescue(id) }
                        } label: {
                            AssetThumbnail(assetID: id, side: 110)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fill)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: verdict.systemImage)
                                        .font(.caption.weight(.bold))
                                        .padding(5)
                                        .background(verdict.color, in: Circle())
                                        .padding(4)
                                }
                        }
                        .accessibilityIdentifier("reviewTile")
                        .accessibilityLabel("Rescue")
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func commitButton(session: SwipeSession) -> some View {
        Button {
            Task {
                await model.commit()
                if model.lastCommit != nil, model.commitError == nil {
                    Haptics.success()
                    showResult = true
                }
            }
        } label: {
            HStack {
                if model.isCommitting { ProgressView().tint(.white) }
                Text(commitTitle(session))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.red, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
        }
        .disabled(model.isCommitting)
        .padding()
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("commitButton")
    }

    private func commitTitle(_ session: SwipeSession) -> String {
        let d = session.deleteIDs.count, h = session.hideIDs.count
        switch (d, h) {
        case (_, 0): return "Delete \(d.formatted())"
        case (0, _): return "Hide \(h.formatted())"
        default: return "Delete \(d.formatted()) & hide \(h.formatted())"
        }
    }
}
