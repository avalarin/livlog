//
//  AppConfig.swift
//  livlogios
//
//  Created by avprokopev on 31.01.2026.
//

import Foundation

nonisolated struct AppConfig {
    static var backendBaseURL: String {
        ServerHost.selected.url
    }

    static var healthCheckURL: URL? {
        URL(string: "\(backendBaseURL)/api/v1/health")
    }

    static var baseURL: String {
        "\(backendBaseURL)/api/v1"
    }

    static var isDevBuild: Bool {
        #if DEV_BUILD
        return true
        #else
        return false
        #endif
    }
}
