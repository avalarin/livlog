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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let collection: CollectionModel
    private let isPreview: Bool

    init(collection: CollectionModel, previewItems: [EntryModel] = []) {
        self.collection = collection
        self.isPreview = !previewItems.isEmpty
        _items = State(initialValue: previewItems)
    }

    @State private var showingAddEntry = false
    @State private var showingSearch = false
    @State private var showingDebugMenu = false
    @State private var isSelectMode = false
    @State private var selectedIDs = Set<String>()
    @State private var showingBulkDeleteAlert = false

    @State private var items: [EntryModel]
    @State private var types: [EntryTypeModel] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var containerWidth: CGFloat = 0

    private func columnCount() -> Int {
        if horizontalSizeClass == .compact {
            return verticalSizeClass == .compact ? 3 : 2
        }
        return containerWidth > 1050 ? 4 : 3
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount())
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false; hasLoaded = true }

        do {
            async let entriesTask = EntryService.shared.getEntries(collectionID: collection.id)
            async let typesTask = TypeService.shared.getTypes()
            items = try await entriesTask
            types = try await typesTask
            selectedIDs.removeAll()
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
            showingError = true
        }
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

    private func bulkDeleteEntries() async {
        let ids = Array(selectedIDs)
        do {
            try await EntryService.shared.bulkDeleteEntries(ids: ids)
            items.removeAll { ids.contains($0.id) }
            selectedIDs.removeAll()
            isSelectMode = false
        } catch {
            errorMessage = "Failed to delete entries: \(error.localizedDescription)"
            showingError = true
            selectedIDs.removeAll()
            isSelectMode = false
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelectMode {
            ToolbarItemGroup(placement: .bottomBar) {
                let allIDs = Set(items.map { $0.id })
                Button {
                    if selectedIDs == allIDs {
                        selectedIDs.removeAll()
                    } else {
                        selectedIDs = allIDs
                    }
                } label: {
                    Text(selectedIDs == allIDs ? "Deselect All" : "Select All")
                }

                Spacer()

                if collection.myRole.canWrite {
                    Button {
                        showingBulkDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(selectedIDs.isEmpty ? Color.secondary : Color.red)
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isSelectMode = false
                    selectedIDs.removeAll()
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }

                Menu {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewMode = viewMode == .grid ? .list : .grid
                        }
                    } label: {
                        Label(
                            viewMode == .grid ? "Switch to List" : "Switch to Grid",
                            systemImage: viewMode == .grid ? "list.bullet" : "square.grid.2x2"
                        )
                    }

                    Button {
                        isSelectMode = true
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }

                    if collection.myRole.canWrite {
                        Divider()

                        Button {
                            Task { await fillWithTestData() }
                        } label: {
                            Label("Fill with Test Data", systemImage: "doc.badge.plus")
                        }

                        Button(role: .destructive) {
                            showingDebugMenu = true
                        } label: {
                            Label("Clear All Data", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
    }

    var body: some View {
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

            ScrollView {
                if items.isEmpty && hasLoaded {
                    EmptyStateView(showingAddEntry: $showingAddEntry, canWrite: collection.myRole.canWrite)
                        .frame(maxWidth: .infinity)
                        .containerRelativeFrame(.vertical, alignment: .center)
                } else {
                    LazyVStack(spacing: 0) {
                        if viewMode == .grid {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(items) { item in
                                    let entryType = types.first { $0.id == item.typeID }
                                    if isSelectMode {
                                        Button {
                                            if selectedIDs.contains(item.id) {
                                                selectedIDs.remove(item.id)
                                            } else {
                                                selectedIDs.insert(item.id)
                                            }
                                        } label: {
                                            EntryCard(
                                                item: item,
                                                entryType: entryType,
                                                onDelete: { await deleteEntry(item) },
                                                isSelectMode: true,
                                                isSelected: selectedIDs.contains(item.id),
                                                canWrite: collection.myRole.canWrite
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        NavigationLink(destination: EntryDetailView(
                                            entryID: item.id, myRole: collection.myRole
                                        )) {
                                            EntryCard(
                                                item: item,
                                                entryType: entryType,
                                                onDelete: { await deleteEntry(item) },
                                                isSelectMode: false,
                                                isSelected: false,
                                                canWrite: collection.myRole.canWrite
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(items) { item in
                                    let entryType = types.first { $0.id == item.typeID }
                                    if isSelectMode {
                                        Button {
                                            if selectedIDs.contains(item.id) {
                                                selectedIDs.remove(item.id)
                                            } else {
                                                selectedIDs.insert(item.id)
                                            }
                                        } label: {
                                            EntryListRow(
                                                item: item,
                                                entryType: entryType,
                                                onDelete: { await deleteEntry(item) },
                                                isSelectMode: true,
                                                isSelected: selectedIDs.contains(item.id),
                                                canWrite: collection.myRole.canWrite
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        NavigationLink(destination: EntryDetailView(
                                            entryID: item.id, myRole: collection.myRole
                                        )) {
                                            EntryListRow(
                                                item: item,
                                                entryType: entryType,
                                                onDelete: { await deleteEntry(item) },
                                                isSelectMode: false,
                                                isSelected: false,
                                                canWrite: collection.myRole.canWrite
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        containerWidth = width
                    }
                            }
            }
            .refreshable {
                await loadData()
            }
            .safeAreaInset(edge: .bottom) {
                if !isSelectMode && collection.myRole.canWrite && hasLoaded {
                    HStack {
                        Spacer()
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showingAddEntry = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle(isSelectMode
            ? (selectedIDs.isEmpty ? "Select Entries" : "\(selectedIDs.count) Selected")
            : collection.name)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAddEntry, onDismiss: {
            Task { await loadData() }
        }) {
            AddEntryView(collection: collection)
        }
        .fullScreenCover(isPresented: $showingSearch) {
            SearchView(types: types)
        }
        .alert(
            "Delete \(selectedIDs.count) \(selectedIDs.count == 1 ? "Entry" : "Entries")",
            isPresented: $showingBulkDeleteAlert
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await bulkDeleteEntries() }
            }
        } message: {
            let noun = selectedIDs.count == 1 ? "entry" : "entries"
            Text("This will permanently delete \(selectedIDs.count) selected \(noun). This action cannot be undone.")
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
           guard !isPreview else { return }
            await loadData()
        }
    }

    // MARK: - Debug Actions

    private struct TestEntryData {
        let title: String
        let description: String
        let score: ScoreRating
        let dateOffset: TimeInterval
        let fields: [String: String]
        let seedIDs: [String]
    }

    private var testEntries: [TestEntryData] {[
        TestEntryData(title: "Inception",
            description: "Inception (2010) is a sci‑fi heist thriller in which Dom Cobb, "
                + "a skilled thief who steals secrets from inside people's dreams.",
            score: .great, dateOffset: 0,
            fields: ["Year": "2010", "Genre": "Sci-Fi, Thriller"],
            seedIDs: ["00000000-0000-0000-0001-000000000001"]),
        TestEntryData(title: "The Dark Knight",
            description: "Heath Ledger's iconic Joker performance.",
            score: .great, dateOffset: -86400 * 2,
            fields: ["Year": "2008", "Genre": "Action, Drama"],
            seedIDs: ["00000000-0000-0000-0001-000000000004"]),
        TestEntryData(title: "1984",
            description: "Orwell's dystopian vision of totalitarian future.",
            score: .great, dateOffset: -86400 * 5,
            fields: ["Year": "1949", "Genre": "Dystopian", "Author": "George Orwell"],
            seedIDs: ["00000000-0000-0000-0001-000000000002"]),
        TestEntryData(title: "Dune",
            description: "Epic science fiction masterpiece.",
            score: .okay, dateOffset: -86400 * 10,
            fields: ["Year": "1965", "Genre": "Sci-Fi", "Author": "Frank Herbert"],
            seedIDs: []),
        TestEntryData(title: "Elden Ring",
            description: "Challenging but incredibly rewarding open-world adventure.",
            score: .great, dateOffset: -86400 * 14,
            fields: ["Year": "2022", "Genre": "Action RPG", "Platform": "PC"],
            seedIDs: ["00000000-0000-0000-0001-000000000003"]),
        TestEntryData(title: "Cyberpunk 2077",
            description: "Finally fixed and pretty good now.",
            score: .okay, dateOffset: -86400 * 20,
            fields: ["Year": "2020", "Genre": "RPG", "Platform": "PlayStation"],
            seedIDs: []),
        TestEntryData(title: "Concert: Radiohead",
            description: "Amazing live performance, goosebumps throughout.",
            score: .great, dateOffset: -86400 * 30,
            fields: [:],
            seedIDs: ["00000000-0000-0000-0001-000000000005"]),
        TestEntryData(title: "Cooking Class",
            description: "Learned to make pasta from scratch. Meh instructor.",
            score: .bad, dateOffset: -86400 * 45,
            fields: [:],
            seedIDs: [])
    ]}

    public func fillWithTestData() async {
        for entry in testEntries {
            do {
                _ = try await EntryService.shared.createEntry(
                    collectionID: collection.id,
                    title: entry.title,
                    description: entry.description,
                    score: entry.score,
                    date: Date().addingTimeInterval(entry.dateOffset),
                    additionalFields: entry.fields,
                    imageData: [],
                    seedImageIDs: entry.seedIDs
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

#Preview("Empty State") {
    NavigationStack {
        ContentView(collection: CollectionModel.previewMyList)
    }
}

#Preview("With Entries") {
    NavigationStack {
        ContentView(collection: CollectionModel.previewMyList, previewItems: EntryModel.previewItems)
    }
}
