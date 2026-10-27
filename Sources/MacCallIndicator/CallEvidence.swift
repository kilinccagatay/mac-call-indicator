import Foundation

// Evidence belongs to a single window. No names, call IDs, or titles are retained.
struct CallEvidence {
    var endControl = false
    var microphoneControl = false
    var elapsedSeconds: Int? = nil
    var preJoinOrRinging = false

    var connected: Bool {
        endControl && microphoneControl && (elapsedSeconds ?? 0) > 0 && !preJoinOrRinging
    }

    mutating func inspectControl(_ label: String) {
        let text = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if ["leave", "end call", "hang up", "hangup", "aramayı bitir", "ayrıl"].contains(text) {
            endControl = true
        }
        if ["mute mic", "unmute mic", "mute", "unmute", "mute audio", "unmute audio"].contains(text) {
            microphoneControl = true
        }
        if ["join now", "accept call", "answer call", "decline call"].contains(text) {
            preJoinOrRinging = true
        }
    }

    mutating func inspectTimer(_ text: String) {
        // Only accept a timer-shaped value, never arbitrary meeting text.
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 3 && $0.allSatisfy(\.isNumber) }) else { return }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count, values.last! < 60,
              values.count == 2 || values[1] < 60 else { return }
        elapsedSeconds = values.reduce(0) { $0 * 60 + $1 }
    }
}
