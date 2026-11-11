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

extension Double {
    /// Pour les cadences (dégâts/s, or/s) : une décimale tant que la valeur est petite.
    var shortRate: String {
        self < 100 ? String(format: "%.1f", self) : short
    }
}

extension TimeInterval {
    /// "2 h 05 min" ou "12 min".
    var readableDuration: String {
        let total = Int(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return String(format: "%d h %02d min", hours, minutes) }
        return "\(max(minutes, 1)) min"
    }
}
