import Foundation

/// Where one frame sits inside its burst. PhotoKit-free so it can be unit tested.
struct BurstInfo: Equatable {
    /// 1-based, in capture order (oldest frame = 1).
    let position: Int
    let count: Int
    /// True when Photos (auto pick) or the user (user pick) flagged this frame
    /// as one of the burst's keepers.
    let isPicked: Bool

    /// Groups frames by burst id and assigns each a capture-order position.
    ///
    /// `frames` is the library snapshot in newest → oldest order, so within one
    /// burst the first frame we see is the *last* one captured. Frames without a
    /// burst id are ignored. Bursts with a single frame still get an entry, since
    /// the badge is a useful hint that Photos' collapsed view hides nothing.
    static func index(newestFirst frames: [(id: String, burstID: String?, isPicked: Bool)]) -> [String: BurstInfo] {
        var membersByBurst: [String: [(id: String, isPicked: Bool)]] = [:]
        for frame in frames {
            guard let burstID = frame.burstID else { continue }
            membersByBurst[burstID, default: []].append((frame.id, frame.isPicked))
        }
        var result: [String: BurstInfo] = [:]
        for members in membersByBurst.values {
            let count = members.count
            for (offset, member) in members.enumerated() {
                result[member.id] = BurstInfo(position: count - offset, count: count, isPicked: member.isPicked)
            }
        }
        return result
    }
}
