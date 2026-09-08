import SwiftUI

/// Transport strip for a video card: play/pause, a draggable scrubber with
/// elapsed/total time, and the mute toggle. Lives in the deck's chrome (not on
/// the card) so dragging the scrubber never competes with the swipe gesture and
/// pinch-zoom on the card leaves it in place.
struct VideoControlsView: View {
    let player: AssetVideoPlayer

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlayback()
                Haptics.light()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!player.isReady)
            .accessibilityIdentifier("playPauseButton")
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Text(timeText(player.currentTime))
                .accessibilityIdentifier("videoElapsed")

            scrubber

            Text(timeText(player.duration))

            Button {
                player.isMuted.toggle()
                Haptics.light()
            } label: {
                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("m", modifiers: [])
            .accessibilityIdentifier("muteButton")
            .accessibilityLabel(player.isMuted ? "Unmute" : "Mute")
        }
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
        .opacity(player.isReady ? 1 : 0.7)
    }

    private var fraction: Double {
        guard player.duration > 0 else { return 0 }
        return min(1, max(0, player.currentTime / player.duration))
    }

    private var scrubber: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = width * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                Capsule().fill(.white).frame(width: max(0, x), height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: player.isScrubbing ? 18 : 12, height: player.isScrubbing ? 18 : 12)
                    .position(x: x, y: geo.size.height / 2)
                    .shadow(radius: 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard player.isReady, player.duration > 0, width > 0 else { return }
                        let f = min(1, max(0, value.location.x / width))
                        player.scrub(to: f * player.duration)
                    }
                    .onEnded { _ in player.endScrubbing() }
            )
        }
        .frame(height: 32)
        .animation(.easeOut(duration: 0.12), value: player.isScrubbing)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("videoScrubber")
        .accessibilityLabel("Scrub video")
        .accessibilityValue(timeText(player.currentTime))
    }

    private func timeText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
