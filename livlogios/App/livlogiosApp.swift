//
//  livlogiosApp.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import SwiftData
import SwiftUI

@main
struct livlogiosApp: App {
    @StateObject private var connectionMonitor = ConnectionMonitor.shared
    @StateObject private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Collection.self,
            Item.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isCheckingAuth {
                    ProgressView()
                } else if appState.isAuthenticated {
                    ContentView()
                        .connectionToast(monitor: connectionMonitor)
                } else {
                    LoginView()
                }
            }
            .environmentObject(appState)
            .onAppear {
                if appState.isAuthenticated {
                    createDefaultCollectionsIfNeeded()
                    connectionMonitor.startMonitoring()
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }

    private func createDefaultCollectionsIfNeeded() {
        let context = sharedModelContainer.mainContext

        let descriptor = FetchDescriptor<Collection>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0

        guard existingCount == 0 else { return }

        for defaultCollection in Collection.defaultCollections {
            let collection = Collection(
                name: defaultCollection.name,
                icon: defaultCollection.icon
            )
            context.insert(collection)
        }

        try? context.save()
    }
}
