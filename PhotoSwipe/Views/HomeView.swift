import SwiftUI
import Photos

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showStartPicker = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if !model.library.hasAccess {
                        accessCard
                    } else if model.library.isLoading && !model.library.hasLoaded {
                        ProgressView("Reading your library…").padding(.top, 40)
                    } else if model.library.assetIDs.isEmpty {
                        ContentUnavailableView("No photos", systemImage: "photo.on.rectangle.angled",
                                               description: Text("Your library has no photos or videos to triage."))
                    } else {
                        if model.hasResumableSession, let session = model.session {
                            resumeCard(session)
                        }
                        startCard
                    }
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .navigationTitle("PhotoSwipe")
            .fullScreenCover(isPresented: $model.isSwiping) {
                SwipeView().environment(model)
            }
            .sheet(isPresented: $showStartPicker) {
                NavigationStack {
                    StartPickerView { id in model.startSession(startID: id) }
                }
                .environment(model)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.library.hasLoaded {
                Text(model.library.assetIDs.count.formatted())
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .accessibilityIdentifier("libraryCount")
                Text("photos & videos in your library")
                    .foregroundStyle(.secondary)
            } else {
                Text("Swipe through your library and decide fast: keep, delete, or hide.")
                    .font(.title3.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Photo access needed", systemImage: "photo.stack")
                .font(.headline)
            Text("PhotoSwipe reads your library to show photos one at a time. Nothing is deleted or hidden until you confirm on the Review screen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if model.library.authorizationStatus == .denied || model.library.authorizationStatus == .restricted {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Allow Photo Access") { Task { await model.requestAccess() } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("allowAccessButton")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func resumeCard(_ session: SwipeSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Session in progress", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            HStack(spacing: 16) {
                stat(session.position, "of \(session.totalCount.formatted())", .secondary)
                stat(session.deleteIDs.count, "to delete", .red)
                stat(session.hideIDs.count, "to hide", .purple)
            }
            HStack {
                Button("Resume") { model.resumeSession() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("resumeButton")
                if session.pendingCount > 0 {
                    NavigationLink("Review") { ReviewView().environment(model) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("homeReviewButton")
                }
                Spacer()
                Button("Discard", role: .destructive) { model.discardSession() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("discardButton")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ value: Int, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("New session", systemImage: "hand.draw")
                .font(.headline)
            Picker("Direction", selection: Binding(
                get: { model.direction },
                set: { model.setDirection($0) }
            )) {
                ForEach(SwipeDirection.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("directionPicker")

            Button {
                model.startSession()
            } label: {
                Label(model.direction == .newestFirst ? "Start from latest" : "Start from oldest", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("startButton")

            Button {
                showStartPicker = true
            } label: {
                Label("Choose where to start…", systemImage: "calendar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("chooseStartButton")

            legend
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("arrow.right", "Keep", .keep)
            legendItem("arrow.left", "Delete", .delete)
            legendItem("arrow.up", "Hide", .hide)
        }
        .font(.caption)
        .padding(.top, 4)
    }

    private func legendItem(_ arrow: String, _ title: String, _ verdict: SwipeDecision) -> some View {
        HStack(spacing: 4) {
            Image(systemName: arrow).foregroundStyle(verdict.color)
            Text(title)
        }
    }
}
