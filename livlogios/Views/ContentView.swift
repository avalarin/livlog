//
//  ContentView.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import SwiftData
import SwiftUI

enum ViewMode: String {
    case grid
    case list
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Item.date, order: .reverse) private var items: [Item]
    @Query(sort: \Collection.createdAt) private var collections: [Collection]

    @AppStorage("viewMode") private var viewMode: ViewMode = .grid

    @State private var showingAddEntry = false
    @State private var showingSmartAdd = false
    @State private var showingCollections = false
    @State private var selectedCollection: Collection?
    @State private var searchText = ""
    @State private var showingDebugMenu = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var filteredItems: [Item] {
        var result = items
        
        if let collection = selectedCollection {
            result = result.filter { $0.collection?.id == collection.id }
        }
        
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.entryDescription.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result
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
                                            NavigationLink(destination: EntryDetailView(item: item)) {
                                                EntryCard(item: item)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                } else {
                                    LazyVStack(spacing: 8) {
                                        ForEach(filteredItems) { item in
                                            NavigationLink(destination: EntryDetailView(item: item)) {
                                                EntryListRow(item: item)
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
                                fillWithTestData()
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
            }
            .alert("Clear All Data", isPresented: $showingDebugMenu) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text("This will delete all \(items.count) entries. This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Debug Actions
    
    private func fillWithTestData() {
        guard let moviesCollection = collections.first(where: { $0.name == "Movies" }),
              let booksCollection = collections.first(where: { $0.name == "Books" }),
              let gamesCollection = collections.first(where: { $0.name == "Games" }) else {
            return
        }
        
        let testItems = [
            Item(
                collection: moviesCollection,
                title: "Inception",
                entryDescription: "A mind-bending masterpiece by Christopher Nolan about dream invasion.",
                score: .great,
                date: Date(),
                additionalFields: ["Year": "2010", "Genre": "Sci-Fi, Thriller"]
            ),
            Item(
                collection: moviesCollection,
                title: "The Dark Knight",
                entryDescription: "Heath Ledger's iconic Joker performance.",
                score: .great,
                date: Date().addingTimeInterval(-86400 * 2),
                additionalFields: ["Year": "2008", "Genre": "Action, Drama"]
            ),
            Item(
                collection: booksCollection,
                title: "1984",
                entryDescription: "Orwell's dystopian vision of totalitarian future.",
                score: .great,
                date: Date().addingTimeInterval(-86400 * 5),
                additionalFields: ["Year": "1949", "Genre": "Dystopian", "Author": "George Orwell"]
            ),
            Item(
                collection: booksCollection,
                title: "Dune",
                entryDescription: "Epic science fiction masterpiece.",
                score: .okay,
                date: Date().addingTimeInterval(-86400 * 10),
                additionalFields: ["Year": "1965", "Genre": "Sci-Fi", "Author": "Frank Herbert"]
            ),
            Item(
                collection: gamesCollection,
                title: "Elden Ring",
                entryDescription: "Challenging but incredibly rewarding open-world adventure.",
                score: .great,
                date: Date().addingTimeInterval(-86400 * 14),
                additionalFields: ["Year": "2022", "Genre": "Action RPG", "Platform": "PC"]
            ),
            Item(
                collection: gamesCollection,
                title: "Cyberpunk 2077",
                entryDescription: "Finally fixed and pretty good now.",
                score: .okay,
                date: Date().addingTimeInterval(-86400 * 20),
                additionalFields: ["Year": "2020", "Genre": "RPG", "Platform": "PlayStation"]
            ),
            Item(
                collection: nil,
                title: "Concert: Radiohead",
                entryDescription: "Amazing live performance, goosebumps throughout.",
                score: .great,
                date: Date().addingTimeInterval(-86400 * 30)
            ),
            Item(
                collection: nil,
                title: "Cooking Class",
                entryDescription: "Learned to make pasta from scratch. Meh instructor.",
                score: .bad,
                date: Date().addingTimeInterval(-86400 * 45)
            )
        ]
        
        for item in testItems {
            modelContext.insert(item)
        }
    }
    
    private func clearAllData() {
        for item in items {
            modelContext.delete(item)
        }
    }
}

struct FilterBar: View {
    @Binding var selectedCollection: Collection?
    let collections: [Collection]
    let items: [Item]
    
    private var collectionsWithItems: [Collection] {
        collections.filter { collection in
            items.contains { $0.collection?.id == collection.id }
        }
    }
    
    private var uncategorizedCount: Int {
        items.filter { $0.collection == nil }.count
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
                    let count = items.filter { $0.collection?.id == collection.id }.count
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
    let item: Item
    @Environment(\.modelContext) private var modelContext
    @State private var showingDeleteAlert = false
    
    private var coverImage: UIImage? {
        guard let firstImageData = item.images.first,
              let image = UIImage(data: firstImageData) else {
            return nil
        }
        return image
    }
    
    private var metadataLine: String {
        let fieldOrder = ["Year", "Genre", "Author", "Platform"]
        let sortedFields = item.additionalFields.sorted { firstItem, secondItem in
            let indexA = fieldOrder.firstIndex(of: firstItem.key) ?? Int.max
            let indexB = fieldOrder.firstIndex(of: secondItem.key) ?? Int.max
            return indexA < indexB
        }
        return sortedFields.map { $0.value }.joined(separator: " • ")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let coverImage = coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                } else {
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
                        Text(item.collection?.icon ?? "📝")
                            .font(.system(size: 48))
                            .opacity(0.5)
                    )
                }

                Text(item.score.emoji)
                    .font(.title3)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text(item.collection?.icon ?? "📝")
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

                if !item.entryDescription.isEmpty {
                    Text(item.entryDescription)
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
                withAnimation {
                    modelContext.delete(item)
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(item.title)\"?")
        }
    }
}

struct EntryListRow: View {
    let item: Item
    @Environment(\.modelContext) private var modelContext
    @State private var showingDeleteAlert = false

    private var coverImage: UIImage? {
        guard let firstImageData = item.images.first,
              let image = UIImage(data: firstImageData) else {
            return nil
        }
        return image
    }

    private var metadataLine: String {
        let fieldOrder = ["Year", "Genre", "Author", "Platform"]
        let sortedFields = item.additionalFields.sorted { firstItem, secondItem in
            let indexA = fieldOrder.firstIndex(of: firstItem.key) ?? Int.max
            let indexB = fieldOrder.firstIndex(of: secondItem.key) ?? Int.max
            return indexA < indexB
        }
        return sortedFields.map { $0.value }.joined(separator: " • ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let coverImage = coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text(item.collection?.icon ?? "📝")
                        .font(.system(size: 40))
                        .frame(width: 60, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                }
            }

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
                withAnimation {
                    modelContext.delete(item)
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
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Collection.self, Item.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    let context = container.mainContext

    // Create collections
    let moviesCollection = Collection(name: "Movies", icon: "🎬")
    let booksCollection = Collection(name: "Books", icon: "📚")
    let gamesCollection = Collection(name: "Games", icon: "🎮")

    context.insert(moviesCollection)
    context.insert(booksCollection)
    context.insert(gamesCollection)

    // Add sample items
    let sampleItems = [
        Item(
            collection: moviesCollection,
            title: "Inception",
            entryDescription: "A mind-bending masterpiece by Christopher Nolan about dream invasion.",
            score: .great,
            date: Date(),
            additionalFields: ["Year": "2010", "Genre": "Sci-Fi, Thriller"]
        ),
        Item(
            collection: booksCollection,
            title: "1984",
            entryDescription: "Orwell's dystopian vision of totalitarian future.",
            score: .great,
            date: Date().addingTimeInterval(-86400 * 5),
            additionalFields: ["Year": "1949", "Genre": "Dystopian", "Author": "George Orwell"]
        ),
        Item(
            collection: gamesCollection,
            title: "Elden Ring",
            entryDescription: "Challenging but incredibly rewarding open-world adventure.",
            score: .great,
            date: Date().addingTimeInterval(-86400 * 14),
            additionalFields: ["Year": "2022", "Genre": "Action RPG", "Platform": "PC"]
        )
    ]

    for item in sampleItems {
        context.insert(item)
    }

    return ContentView()
        .modelContainer(container)
}
