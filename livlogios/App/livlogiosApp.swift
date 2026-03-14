//
//  livlogiosApp.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import SwiftUI

@main
struct livlogiosApp: App { // swiftlint:disable:this type_name
    @StateObject private var connectionMonitor = ConnectionMonitor.shared
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isCheckingAuth {
                    ProgressView()
                } else if appState.isAuthenticated {
                    if appState.needsOnboarding {
                        OnboardingView()
                    } else {
                        CollectionsView()
                            .connectionToast(monitor: connectionMonitor)
                    }
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
            .onChange(of: appState.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    connectionMonitor.startMonitoring()
                } else {
                    connectionMonitor.stopMonitoring()
                }
            }
        }
    }
}
