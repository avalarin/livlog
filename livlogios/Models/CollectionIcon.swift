import SwiftUI

enum CollectionIcon: Equatable {
    case system(String)
    case emoji(String)

    static let allSystemIcons: [String] = [
        "folder", "bookmark", "movie", "music", "musical-note", "music-library",
        "music-record", "cymbals", "radio-waves", "cameras", "image", "flash-on",
        "albums", "briefcase", "price-tag", "gift", "user", "male-user"
    ]

    init(raw: String) {
        if raw.hasPrefix("system:") {
            let name = String(raw.dropFirst(7))
            self = .system(name)
        } else if raw.hasPrefix("emoji:") {
            let emoji = String(raw.dropFirst(6))
            self = .emoji(emoji)
        } else {
            self = .emoji(raw)
        }
    }

    var rawValue: String {
        switch self {
        case .system(let name): return "system:\(name)"
        case .emoji(let emoji): return "emoji:\(emoji)"
        }
    }
}

struct CollectionIconView: View {
    let icon: CollectionIcon
    let color: CollectionColor
    let size: CGFloat

    init(icon: CollectionIcon, color: CollectionColor, size: CGFloat = 44) {
        self.icon = icon
        self.color = color
        self.size = size
    }

    init(iconRaw: String, colorRaw: String, size: CGFloat = 44) {
        self.icon = CollectionIcon(raw: iconRaw)
        self.color = CollectionColor(rawValue: colorRaw) ?? .dodgerBlue
        self.size = size
    }

    var body: some View {
        Group {
            switch icon {
            case .system(let name):
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(color.color)
                    .padding(size * 0.15)
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: size * 0.55))
            }
        }
        .frame(width: size, height: size)
        .background(color.color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}
