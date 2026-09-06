import SwiftUI

extension SwipeDecision {
    var color: Color {
        switch self {
        case .keep: return .green
        case .delete: return .red
        case .hide: return .purple
        }
    }

    var label: String {
        switch self {
        case .keep: return "KEEP"
        case .delete: return "DELETE"
        case .hide: return "HIDE"
        }
    }

    var systemImage: String {
        switch self {
        case .keep: return "checkmark"
        case .delete: return "trash"
        case .hide: return "eye.slash"
        }
    }
}

enum Haptics {
    static func decision(_ verdict: SwipeDecision) {
        let style: UIImpactFeedbackGenerator.FeedbackStyle = verdict == .delete ? .heavy : .medium
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
