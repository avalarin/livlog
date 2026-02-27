//
//  livlogiosApp.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import SwiftUI

@main
struct livlogiosApp: App {
    @StateObject private var connectionMonitor = ConnectionMonitor.shared
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isCheckingAuth {
                    ProgressView()
                } else if appState.isAuthenticated {
                    CollectionsView()
                        .connectionToast(monitor: connectionMonitor)
                } else {
                    LoginView()
                }
            }
            .environmentObject(appState)
            .onAppear {
                if appState.isAuthenticated {
                    connectionMonitor.startMonitoring()
                }
            }
        }
    }
}
