import Foundation

extension Double {
    /// Notation courte pour les grands nombres : 1234 -> "1.23K".
    var short: String {
        let suffixes = ["", "K", "M", "B", "T", "aa", "ab", "ac", "ad", "ae", "af", "ag"]
        var value = self
        var index = 0
        while abs(value) >= 1000, index < suffixes.count - 1 {
            value /= 1000
            index += 1
        }
        if index == 0 { return String(Int(value.rounded(.down))) }
        let digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        let factor = pow(10, Double(digits))
        let truncated = (value * factor).rounded(.down) / factor
        return String(format: "%.\(digits)f", truncated) + suffixes[index]
    }
}

extension TimeInterval {
    /// Compte à rebours : "1 h 05 min", "3 min 20 s", "45 s".
    var countdown: String {
        let total = max(Int(self.rounded(.up)), 0)
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return String(format: "%d h %02d min", hours, minutes) }
        if minutes > 0 { return String(format: "%d min %02d s", minutes, seconds) }
        return "\(seconds) s"
    }

    /// Durée annoncée : "2 h", "1 h 30", "20 min", "45 s".
    var shortDuration: String {
        let total = max(Int(self.rounded()), 1)
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return minutes > 0 ? String(format: "%d h %02d", hours, minutes) : "\(hours) h" }
        if minutes > 0 { return seconds > 0 && minutes < 10 ? "\(minutes) min \(seconds) s" : "\(minutes) min" }
        return "\(seconds) s"
    }
}
