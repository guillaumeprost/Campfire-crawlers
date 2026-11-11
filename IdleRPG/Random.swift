import Foundation

/// Générateur aléatoire reproductible (SplitMix64).
/// Avec le même état de départ il rend toujours la même suite de tirages :
/// c'est ce qui permet de calculer à l'avance l'issue d'une expédition.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
