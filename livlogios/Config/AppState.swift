//
//  AppState.swift
//  livlogios
//
//  Created by Claude Code on 31.01.2026.
//

import Combine
import Foundation

@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?
    @Published var isCheckingAuth: Bool = true

    let authService: AuthService

    init() {
        authService = AuthService()
        Task {
            await checkAuth()
        }
    }

    func checkAuth() async {
        isCheckingAuth = true
        isAuthenticated = await authService.checkAuthStatus()
        currentUser = authService.currentUser
        isCheckingAuth = false
    }

    func logout() async {
        await authService.logout()
        isAuthenticated = false
        currentUser = nil
    }

    func deleteAccount() async throws {
        try await authService.deleteAccount()
        isAuthenticated = false
        currentUser = nil
    }
}
