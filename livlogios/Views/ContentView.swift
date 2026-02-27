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
    @State private var searchText = ""
    @State private var showingDebugMenu = false
    @State private var isSelectMode = false
    @State private var selectedIDs = Set<String>()
    @State private var showingBulkDeleteAlert = false

    @State private var items: [EntryModel]
    @State private var types: [EntryTypeModel] = []
    @State private var isLoading = false
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

    var filteredItems: [EntryModel] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let entriesTask = EntryService.shared.getEntries(collectionID: collection.id)
            async let typesTask = TypeService.shared.getTypes()
            items = try await entriesTask
            types = try await typesTask
            selectedIDs.removeAll()
        } catch {
            guard !Task.isCancelled else { return }
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

            if items.isEmpty && !isLoading {
                EmptyStateView(showingAddEntry: $showingAddEntry)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredItems.isEmpty && !searchText.isEmpty {
                            VStack(spacing: 12) {
                                Text("No matches")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text("Try adjusting your search")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            if viewMode == .grid {
                                LazyVGrid(columns: gridColumns, spacing: 12) {
                                    ForEach(filteredItems) { item in
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
                                                    isSelected: selectedIDs.contains(item.id)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            NavigationLink(destination: EntryDetailView(entryID: item.id)) {
                                                EntryCard(
                                                    item: item,
                                                    entryType: entryType,
                                                    onDelete: { await deleteEntry(item) },
                                                    isSelectMode: false,
                                                    isSelected: false
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            } else {
                                LazyVStack(spacing: 8) {
                                    ForEach(filteredItems) { item in
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
                                                    isSelected: selectedIDs.contains(item.id)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            NavigationLink(destination: EntryDetailView(entryID: item.id)) {
                                                EntryListRow(
                                                    item: item,
                                                    entryType: entryType,
                                                    onDelete: { await deleteEntry(item) },
                                                    isSelectMode: false,
                                                    isSelected: false
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        containerWidth = width
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !isSelectMode {
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                                TextField("Search entries...", text: $searchText)
                                    .textFieldStyle(.automatic)
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                            Button {
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

                .refreshable {
                    await loadData()
                }
            }
        }
        .navigationTitle(isSelectMode
            ? (selectedIDs.isEmpty ? "Select Entries" : "\(selectedIDs.count) Selected")
            : collection.name)
        .toolbar {
            if isSelectMode {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        let allIDs = Set(filteredItems.map { $0.id })
                        if selectedIDs == allIDs {
                            selectedIDs.removeAll()
                        } else {
                            selectedIDs = allIDs
                        }
                    } label: {
                        Text(selectedIDs == Set(filteredItems.map { $0.id }) ? "Deselect All" : "Select All")
                    }

                    Spacer()

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
                if isSelectMode {
                    Button {
                        isSelectMode = false
                        selectedIDs.removeAll()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                } else {
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
                            searchText = ""
                            isSelectMode = true
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
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
                        Image(systemName: "ellipsis")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            AddEntryView(collection: collection)
        }
        .alert("Delete \(selectedIDs.count) \(selectedIDs.count == 1 ? "Entry" : "Entries")", isPresented: $showingBulkDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await bulkDeleteEntries() }
            }
        } message: {
            Text("This will permanently delete \(selectedIDs.count) selected \(selectedIDs.count == 1 ? "entry" : "entries"). This action cannot be undone.")
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
        .onChange(of: searchText) {
            if isSelectMode {
                selectedIDs.removeAll()
            }
        }
        .task {
            guard !isPreview else { return }
            await loadData()
        }
    }

    // MARK: - Debug Actions

    public func fillWithTestData() async {
        let testData: [(String, String, ScoreRating, TimeInterval, [String: String], [String])] = [
            ("Inception", "Inception (2010) is a sci‑fi heist thriller in which Dom Cobb, a skilled thief who steals secrets from inside people's dreams, is offered a chance to clear his criminal record.",
             .great, 0, ["Year": "2010", "Genre": "Sci-Fi, Thriller"],
             ["00000000-0000-0000-0001-000000000001"]),
            ("The Dark Knight", "Heath Ledger's iconic Joker performance.",
             .great, -86400 * 2, ["Year": "2008", "Genre": "Action, Drama"],
             ["00000000-0000-0000-0001-000000000004"]),
            ("1984", "Orwell's dystopian vision of totalitarian future.",
             .great, -86400 * 5, ["Year": "1949", "Genre": "Dystopian", "Author": "George Orwell"],
             ["00000000-0000-0000-0001-000000000002"]),
            ("Dune", "Epic science fiction masterpiece.",
             .okay, -86400 * 10, ["Year": "1965", "Genre": "Sci-Fi", "Author": "Frank Herbert"],
             []),
            ("Elden Ring", "Challenging but incredibly rewarding open-world adventure.",
             .great, -86400 * 14, ["Year": "2022", "Genre": "Action RPG", "Platform": "PC"],
             ["00000000-0000-0000-0001-000000000003"]),
            ("Cyberpunk 2077", "Finally fixed and pretty good now.",
             .okay, -86400 * 20, ["Year": "2020", "Genre": "RPG", "Platform": "PlayStation"],
             []),
            ("Concert: Radiohead", "Amazing live performance, goosebumps throughout.",
             .great, -86400 * 30, [:],
             ["00000000-0000-0000-0001-000000000005"]),
            ("Cooking Class", "Learned to make pasta from scratch. Meh instructor.",
             .bad, -86400 * 45, [:],
             [])
        ]

        for (title, description, score, dateOffset, fields, seedIDs) in testData {
            do {
                _ = try await EntryService.shared.createEntry(
                    collectionID: collection.id,
                    title: title,
                    description: description,
                    score: score,
                    date: Date().addingTimeInterval(dateOffset),
                    additionalFields: fields,
                    imageData: [],
                    seedImageIDs: seedIDs
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

struct EntryCard: View {
    let item: EntryModel
    let entryType: EntryTypeModel?
    let onDelete: () async -> Void
    var isSelectMode: Bool = false
    var isSelected: Bool = false

    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    @State private var coverImage: UIImage?

    private var metadataLine: String {
        let line = item.additionalFields.values.joined(separator: "・")
        return line.isEmpty ? "-" : line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
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
                    Text(entryType?.icon ?? "📝")
                        .font(.system(size: 48))
                        .opacity(0.5)
                )

                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .layoutPriority(-1)
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(item.score.emoji)
                    .font(.title3)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    Text(entryType?.icon ?? "📝")
                        .font(.caption)
                    Text(item.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if !metadataLine.isEmpty {
                    Text(metadataLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !item.description.isEmpty {
                    Text(item.description + "\n")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).fill(isSelected ? Color.gray.opacity(0.2) : Color.clear))
        .overlay(alignment: .bottomTrailing) {
            if isSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(8)
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .opacity(isDeleting ? 0.5 : 1.0)
        .if(!isSelectMode) { view in
            view.contextMenu {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
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
        .task {
            await loadCoverImage()
        }
    }

    private func loadCoverImage() async {
        let cover = item.images.first { $0.isCover }
            ?? item.images.first
        guard let cover else { return }
        guard let data = try? await EntryService.shared.getImage(
            imageID: cover.id
        ) else { return }
        coverImage = UIImage(data: data)
    }
}

struct EntryListRow: View {
    let item: EntryModel
    let entryType: EntryTypeModel?
    let onDelete: () async -> Void
    var isSelectMode: Bool = false
    var isSelected: Bool = false

    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    @State private var coverImage: UIImage?

    private var metadataLine: String {
        if item.description.isEmpty {
            return "(no notes)"
        }
        let firstLine = item.description.components(separatedBy: .newlines).first ?? ""
        return firstLine.isEmpty ? "(no notes)" : firstLine
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text(entryType?.icon ?? "📝")
                    .font(.system(size: 40))
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.1))
                    )
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
                if isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                } else {
                    Text(item.score.emoji)
                        .font(.title3)
                }

                Text(item.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color.gray.opacity(0.2) : Color.clear))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        .opacity(isDeleting ? 0.5 : 1.0)
        .if(!isSelectMode) { view in
            view.contextMenu {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
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
        .task {
            await loadCoverImage()
        }
    }

    private func loadCoverImage() async {
        let cover = item.images.first { $0.isCover }
            ?? item.images.first
        guard let cover else { return }
        guard let data = try? await EntryService.shared.getImage(
            imageID: cover.id
        ) else { return }
        coverImage = UIImage(data: data)
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

// MARK: - View Extensions

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
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
