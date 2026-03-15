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
                    CollectionsView()
                        .connectionToast(monitor: connectionMonitor)
                        .sheet(isPresented: .constant(appState.needsOnboarding)) {
                            EditDisplayNameView(isOnboarding: true)
                        }
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else {
                    LoginView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: appState.isAuthenticated)
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
