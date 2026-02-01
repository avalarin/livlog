//
//  AppConfig.swift
//  livlogios
//
//  Created by avprokopev on 31.01.2026.
//

import Foundation

enum AppEnvironment {
    case preview
    case development
    case production

    var backendBaseURL: String {
        switch self {
        case .preview:
            return "http://localhost:8080"
        case .development:
            return "http://192.168.1.42:8080"
        case .production:
            return "https://prod.livlog.avalarin.net"
        }
    }

    var healthCheckURL: URL? {
        URL(string: "\(backendBaseURL)/api/v1/health")
    }
}

struct AppConfig {
    static var current: AppEnvironment {
        #if DEBUG
        // Check if running in SwiftUI Preview
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .preview
        }
        return .development
        #else
        return .production
        #endif
    }

    static var backendBaseURL: String {
        current.backendBaseURL
    }

    static var healthCheckURL: URL? {
        current.healthCheckURL
    }

    static var baseURL: String {
        "\(backendBaseURL)/api/v1"
    }
}
