//
//  BackendService.swift
//  livlogios
//
//  Created by avprokopev on 31.01.2026.
//

import Foundation

struct DatabaseStatus: Decodable {
    let status: String
    let pingMs: Int

    enum CodingKeys: String, CodingKey {
        case status
        case pingMs = "ping_ms"
    }
}

struct HealthResponse: Decodable {
    let status: String
    let timestamp: String
    let version: String
    let uptime: String
    let database: DatabaseStatus

    var isHealthy: Bool {
        status == "ok" && database.status == "connected"
    }
}

actor BackendService {
    static let shared = BackendService()

    private init() {}

    func checkHealth() async -> Bool {
        guard let url = AppConfig.healthCheckURL else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            let healthResponse = try JSONDecoder().decode(HealthResponse.self, from: data)
            return healthResponse.isHealthy
        } catch {
            return false
        }
    }
}
