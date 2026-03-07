import SwiftUI

enum CollectionColor: String, CaseIterable {
    case dodgerBlue = "dodger-blue"
    case dustyGrape = "dusty-grape"
    case strawGold = "straw-gold"
    case rosewood = "rosewood"
    case coralGlow = "coral-glow"
    case vibrantCoral = "vibrant-coral"
    case vintageGrape = "vintage-grape"
    case yellowGreen = "yellow-green"
    case granite = "granite"
    case verdigris = "verdigris"

    var color: Color {
        switch self {
        case .dodgerBlue: return Color(hex: 0x2191FB)
        case .dustyGrape: return Color(hex: 0x6E5CA3)
        case .strawGold: return Color(hex: 0xE9D758)
        case .rosewood: return Color(hex: 0xBA274A)
        case .coralGlow: return Color(hex: 0xFF8552)
        case .vibrantCoral: return Color(hex: 0xFF595E)
        case .vintageGrape: return Color(hex: 0x4C3549)
        case .yellowGreen: return Color(hex: 0x8AC926)
        case .granite: return Color(hex: 0x3F5E5A)
        case .verdigris: return Color(hex: 0x2A9D8F)
        }
    }

    var displayName: String {
        switch self {
        case .dodgerBlue: return "Blue"
        case .dustyGrape: return "Grape"
        case .strawGold: return "Gold"
        case .rosewood: return "Rose"
        case .coralGlow: return "Coral"
        case .vibrantCoral: return "Red"
        case .vintageGrape: return "Plum"
        case .yellowGreen: return "Green"
        case .granite: return "Granite"
        case .verdigris: return "Teal"
        }
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
