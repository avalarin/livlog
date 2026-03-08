//
//  ServerHost.swift
//  livlogios
//

import Foundation

nonisolated enum ServerHost: String, CaseIterable {
    case local
    case dev
    case prod

    var url: String {
        switch self {
        case .local:
            return "http://192.168.1.42:8080"
        case .dev:
            return "https://livlog-api.main.avalarin.net"
        case .prod:
            return "https://livlog-api.prod.avalarin.net"
        }
    }

    var label: String {
        rawValue
    }

    var displayHost: String {
        switch self {
        case .local:
            return "192.168.1.42:8080"
        case .dev:
            return "livlog-api.main.avalarin.net"
        case .prod:
            return "livlog-api.prod.avalarin.net"
        }
    }

    static var selected: ServerHost {
        get {
            let raw = UserDefaults.standard.string(forKey: "selectedServerHost") ?? ""
            return ServerHost(rawValue: raw) ?? .dev
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "selectedServerHost")
        }
    }
}
