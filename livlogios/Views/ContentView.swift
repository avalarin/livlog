//
//  ContentView.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import SwiftUI

enum ViewMode: String {
    case grid
    case list
}

struct ContentView: View {
    @AppStorage("viewMode") private var viewMode: ViewMode = .grid

    @State private var showingAddEntry = false
    @State private var showingSmartAdd = false
    @State private var showingCollections = false
    @State private var selectedCollection: CollectionModel?
    @State private var searchText = ""
    @State private var showingDebugMenu = false

    @State private var items: [EntryModel] = []
    @State private var collections: [CollectionModel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var filteredItems: [EntryModel] {
        var result = items

        if let collection = selectedCollection {
            result = result.filter { $0.collectionID == collection.id }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let collectionsTask = CollectionService.shared.getCollections()
            async let entriesTask = EntryService.shared.getEntries()

            collections = try await collectionsTask
            items = try await entriesTask
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
            showingError = true
        }

        isLoading = false
    }

    func deleteEntry(_ entry: EntryModel) async {
        do {
            try await EntryService.shared.deleteEntry(id: entry.id)
            items.removeAll { $0.id == entry.id }
        } catch {
            errorMessage = "Failed to delete entry: \(error.localizedDescription)"
            showingError = true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if items.isEmpty {
                    EmptyStateView(showingAddEntry: $showingAddEntry)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            FilterBar(
                                selectedCollection: $selectedCollection,
                                collections: collections,
                                items: items
                            )
                            .padding(.bottom, 16)
                            
                            if filteredItems.isEmpty {
                                VStack(spacing: 12) {
                                    Text("No matches")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    Text("Try adjusting your filters")
                                        .font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            } else {
                                if viewMode == .grid {
                                    LazyVGrid(columns: columns, spacing: 12) {
                                        ForEach(filteredItems) { item in
                                            let collection = collections.first { $0.id == item.collectionID }
                                            NavigationLink(destination: EntryDetailView(entryID: item.id)) {
                                                EntryCard(
                                                    item: item,
                                                    collection: collection,
                                                    onDelete: {
                                                        await deleteEntry(item)
                                                    }
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                } else {
                                    LazyVStack(spacing: 8) {
                                        ForEach(filteredItems) { item in
                                            let collection = collections.first { $0.id == item.collectionID }
                                            NavigationLink(destination: EntryDetailView(entryID: item.id)) {
                                                EntryListRow(
                                                    item: item,
                                                    collection: collection,
                                                    onDelete: {
                                                        await deleteEntry(item)
                                                    }
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.bottom, 100)
                    }
                    .searchable(text: $searchText, prompt: "Search entries...")
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                viewMode = viewMode == .grid ? .list : .grid
                            }
                        } label: {
                            Image(systemName: viewMode == .grid ? "square.grid.2x2" : "list.bullet")
                                .symbolRenderingMode(.hierarchical)
                        }

                        Menu {
                            Button {
                                showingCollections = true
                            } label: {
                                Label("Manage Collections", systemImage: "folder")
                            }

                            Divider()

                            Button {
                                Task {
                                    await fillWithTestData()
                                }
                            } label: {
                                Label("Fill with Test Data", systemImage: "doc.badge.plus")
                            }

                            Button(role: .destructive) {
                                showingDebugMenu = true
                            } label: {
                                Label("Clear All Data", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "gear")
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingSmartAdd = true
                        } label: {
                            Label("Quick Add (AI)", systemImage: "sparkles")
                        }
                        
                        Button {
                            showingAddEntry = true
                        } label: {
                            Label("Manual Add", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                AddEntryView()
            }
            .sheet(isPresented: $showingSmartAdd) {
                SmartAddEntryView()
            }
            .sheet(isPresented: $showingCollections) {
                CollectionsView()
                    .onDisappear {
                        Task {
                            await loadData()
                        }
                    }
            }
            .alert("Clear All Data", isPresented: $showingDebugMenu) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    Task {
                        await clearAllData()
                    }
                }
            } message: {
                Text("This will delete all \(items.count) entries. This action cannot be undone.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .task {
                await loadData()
            }
            .refreshable {
                await loadData()
            }
        }
    }
    
    // MARK: - Debug Actions

    private func fillWithTestData() async {
        guard let moviesCollection = collections.first(where: { $0.name == "Movies" }),
              let booksCollection = collections.first(where: { $0.name == "Books" }),
              let gamesCollection = collections.first(where: { $0.name == "Games" }) else {
            return
        }

        let testData: [(String?, String, String, ScoreRating, TimeInterval, [String: String])] = [
            (moviesCollection.id, "Inception", "A mind-bending masterpiece by Christopher Nolan about dream invasion.", .great, 0, ["Year": "2010", "Genre": "Sci-Fi, Thriller"]),
            (moviesCollection.id, "The Dark Knight", "Heath Ledger's iconic Joker performance.", .great, -86400 * 2, ["Year": "2008", "Genre": "Action, Drama"]),
            (booksCollection.id, "1984", "Orwell's dystopian vision of totalitarian future.", .great, -86400 * 5, ["Year": "1949", "Genre": "Dystopian", "Author": "George Orwell"]),
            (booksCollection.id, "Dune", "Epic science fiction masterpiece.", .okay, -86400 * 10, ["Year": "1965", "Genre": "Sci-Fi", "Author": "Frank Herbert"]),
            (gamesCollection.id, "Elden Ring", "Challenging but incredibly rewarding open-world adventure.", .great, -86400 * 14, ["Year": "2022", "Genre": "Action RPG", "Platform": "PC"]),
            (gamesCollection.id, "Cyberpunk 2077", "Finally fixed and pretty good now.", .okay, -86400 * 20, ["Year": "2020", "Genre": "RPG", "Platform": "PlayStation"]),
            (nil, "Concert: Radiohead", "Amazing live performance, goosebumps throughout.", .great, -86400 * 30, [:]),
            (nil, "Cooking Class", "Learned to make pasta from scratch. Meh instructor.", .bad, -86400 * 45, [:])
        ]

        for (collectionID, title, description, score, dateOffset, fields) in testData {
            do {
                _ = try await EntryService.shared.createEntry(
                    collectionID: collectionID,
                    title: title,
                    description: description,
                    score: score,
                    date: Date().addingTimeInterval(dateOffset),
                    additionalFields: fields,
                    imageData: []
                )
            } catch {
                errorMessage = "Failed to create test entry: \(error.localizedDescription)"
                showingError = true
                return
            }
        }

        await loadData()
    }

    private func clearAllData() async {
        for item in items {
            do {
                try await EntryService.shared.deleteEntry(id: item.id)
            } catch {
                errorMessage = "Failed to delete entry: \(error.localizedDescription)"
                showingError = true
                return
            }
        }

        await loadData()
    }
}

struct FilterBar: View {
    @Binding var selectedCollection: CollectionModel?
    let collections: [CollectionModel]
    let items: [EntryModel]

    private var collectionsWithItems: [CollectionModel] {
        collections.filter { collection in
            items.contains { $0.collectionID == collection.id }
        }
    }

    private var uncategorizedCount: Int {
        items.filter { $0.collectionID == nil }.count
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                FilterPill(
                    title: "All",
                    icon: "🌟",
                    count: items.count,
                    isSelected: selectedCollection == nil
                ) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedCollection = nil
                    }
                }
                
                ForEach(collectionsWithItems) { collection in
                    let count = items.filter { $0.collectionID == collection.id }.count
                    FilterPill(
                        title: collection.name,
                        icon: collection.icon,
                        count: count,
                        isSelected: selectedCollection?.id == collection.id
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedCollection = collection
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct FilterPill: View {
    let title: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(icon)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.3) : Color(.systemGray5))
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color(.systemGray6))
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct EntryCard: View {
    let item: EntryModel
    let collection: CollectionModel?
    let onDelete: () async -> Void

    @State private var showingDeleteAlert = false
    @State private var isDeleting = false

    private var metadataLine: String {
        // Show first line of notes
        if item.description.isEmpty {
            return "(no notes)"
        }
        let firstLine = item.description.components(separatedBy: .newlines).first ?? ""
        return firstLine.isEmpty ? "(no notes)" : firstLine
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.3),
                        Color.accentColor.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .overlay(
                    Text(collection?.icon ?? "📝")
                        .font(.system(size: 48))
                        .opacity(0.5)
                )

                Text(item.score.emoji)
                    .font(.title3)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text(collection?.icon ?? "📝")
                        .font(.caption)
                    Text(item.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                if !metadataLine.isEmpty {
                    Text(metadataLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !item.description.isEmpty {
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .opacity(isDeleting ? 0.5 : 1.0)
        .contextMenu {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Entry", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    await onDelete()
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(item.title)\"?")
        }
    }
}

struct EntryListRow: View {
    let item: EntryModel
    let collection: CollectionModel?
    let onDelete: () async -> Void

    @State private var showingDeleteAlert = false
    @State private var isDeleting = false

    private var metadataLine: String {
        // Show first line of notes
        if item.description.isEmpty {
            return "(no notes)"
        }
        let firstLine = item.description.components(separatedBy: .newlines).first ?? ""
        return firstLine.isEmpty ? "(no notes)" : firstLine
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(collection?.icon ?? "📝")
                .font(.system(size: 40))
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentColor.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if !metadataLine.isEmpty {
                        Text(metadataLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.score.emoji)
                    .font(.title3)

                Text(item.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .opacity(isDeleting ? 0.5 : 1.0)
        .contextMenu {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Entry", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    await onDelete()
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(item.title)\"?")
        }
    }
}

struct EmptyStateView: View {
    @Binding var showingAddEntry: Bool

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Text("📝")
                    .font(.system(size: 72))

                Text("Your Life Log is Empty")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Start tracking movies, books, games,\nand everything else you experience!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingAddEntry = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                    Text("Add First Entry")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                )
                .foregroundStyle(.white)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
