//
//  CollectionsView.swift
//  livlogios
//
//  Created by avprokopev on 14.01.2026.
//

import SwiftUI

struct CollectionsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var collections: [CollectionModel] = []
    @State private var entries: [EntryModel] = []
    @State private var showingAddCollection = false
    @State private var editingCollection: CollectionModel?
    @State private var showingDeleteAlert = false
    @State private var collectionToDelete: CollectionModel?

    @State private var isLoading = false
    @State private var isCreatingDefaults = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    List {
                        ForEach(collections) { collection in
                            let entryCount = entries.filter { $0.collectionID == collection.id }.count
                            CollectionRow(
                                collection: collection,
                                entryCount: entryCount,
                                onEdit: { editingCollection = collection },
                                onDelete: {
                                    collectionToDelete = collection
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddCollection = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCollection) {
                AddEditCollectionView(mode: .add)
                    .onDisappear {
                        Task {
                            await loadData()
                        }
                    }
            }
            .sheet(item: $editingCollection) { collection in
                AddEditCollectionView(mode: .edit(collection))
                    .onDisappear {
                        Task {
                            await loadData()
                        }
                    }
            }
            .alert("Delete Collection", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    collectionToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let collection = collectionToDelete {
                        Task {
                            await deleteCollection(collection)
                        }
                    }
                }
            } message: {
                if let collection = collectionToDelete {
                    let entryCount = entries.filter { $0.collectionID == collection.id }.count
                    Text("Delete \"\(collection.name)\" and all its \(entryCount) entries? This cannot be undone.")
                }
            }
            .overlay {
                if collections.isEmpty && !isLoading {
                    ContentUnavailableView {
                        Label("No Collections", systemImage: "folder")
                    } description: {
                        Text("Create a collection to organize your entries")
                    } actions: {
                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await createDefaultCollections()
                                }
                            } label: {
                                if isCreatingDefaults {
                                    ProgressView()
                                } else {
                                    Text("Create Default Collections")
                                }
                            }
                            .disabled(isCreatingDefaults)
                            .buttonStyle(.borderedProminent)

                            Button("Add Custom Collection") {
                                showingAddCollection = true
                            }
                        }
                    }
                }
            }
            .task {
                await loadData()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            async let collectionsTask = CollectionService.shared.getCollections()
            async let entriesTask = EntryService.shared.getEntries()

            collections = try await collectionsTask
            entries = try await entriesTask
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
            showError = true
        }

        isLoading = false
    }

    private func createDefaultCollections() async {
        isCreatingDefaults = true
        errorMessage = nil

        do {
            _ = try await CollectionService.shared.createDefaultCollections()
            await loadData()
        } catch {
            errorMessage = "Failed to create default collections: \(error.localizedDescription)"
            showError = true
        }

        isCreatingDefaults = false
    }

    private func deleteCollection(_ collection: CollectionModel) async {
        errorMessage = nil

        do {
            try await CollectionService.shared.deleteCollection(id: collection.id)
            await loadData()
        } catch {
            errorMessage = "Failed to delete collection: \(error.localizedDescription)"
            showError = true
        }

        collectionToDelete = nil
    }
}

struct CollectionRow: View {
    let collection: CollectionModel
    let entryCount: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(collection.icon)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.headline)

                Text("\(entryCount) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }
}

struct AddEditCollectionView: View {
    enum Mode: Identifiable {
        case add
        case edit(CollectionModel)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let c): return "edit-\(c.id)"
            }
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedIcon: String = "📁"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    private let emojiOptions = [
        "📁", "🎬", "📚", "🎮", "🎵", "🎨", "🍿", "📺", "🎭", "🎪",
        "✈️", "🌍", "🍽️", "☕️", "🏋️", "⚽️", "🎾", "🎯", "🎲", "🎸",
        "📷", "💼", "🎓", "💡", "🔧", "🛠️", "🎁", "💎", "🌟", "✨"
    ]
    
    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }
    
    private var title: String {
        isEditing ? "Edit Collection" : "New Collection"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Collection name", text: $name)
                }
                
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojiOptions, id: \.self) { emoji in
                            Button {
                                selectedIcon = emoji
                            } label: {
                                Text(emoji)
                                    .font(.title)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedIcon == emoji ? Color.accentColor.opacity(0.2) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedIcon == emoji ? Color.accentColor : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    HStack {
                        Text("Preview")
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Text(selectedIcon)
                                .font(.title3)
                            Text(name.isEmpty ? "Collection Name" : name)
                                .foregroundStyle(name.isEmpty ? .secondary : .primary)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await saveCollection()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
            .onAppear {
                if case .edit(let collection) = mode {
                    name = collection.name
                    selectedIcon = collection.icon
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }

    private func saveCollection() async {
        isSaving = true
        errorMessage = nil

        do {
            switch mode {
            case .add:
                _ = try await CollectionService.shared.createCollection(name: name, icon: selectedIcon)
            case .edit(let collection):
                _ = try await CollectionService.shared.updateCollection(id: collection.id, name: name, icon: selectedIcon)
            }
            dismiss()
        } catch {
            errorMessage = "Failed to save collection: \(error.localizedDescription)"
            showError = true
            isSaving = false
        }
    }
}

#Preview {
    CollectionsView()
}
