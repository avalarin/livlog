//
//  CollectionsView.swift
//  livlogios
//
//  Created by avprokopev on 14.01.2026.
//

import SwiftUI
import SwiftData

struct CollectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    
    @State private var showingAddCollection = false
    @State private var editingCollection: Collection?
    @State private var showingDeleteAlert = false
    @State private var collectionToDelete: Collection?
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(collections) { collection in
                    CollectionRow(
                        collection: collection,
                        onEdit: { editingCollection = collection },
                        onDelete: {
                            collectionToDelete = collection
                            showingDeleteAlert = true
                        }
                    )
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
            }
            .sheet(item: $editingCollection) { collection in
                AddEditCollectionView(mode: .edit(collection))
            }
            .alert("Delete Collection", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    collectionToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let collection = collectionToDelete {
                        deleteCollection(collection)
                    }
                }
            } message: {
                if let collection = collectionToDelete {
                    Text("Delete \"\(collection.name)\" and all its \(collection.items.count) entries? This cannot be undone.")
                }
            }
            .overlay {
                if collections.isEmpty {
                    ContentUnavailableView {
                        Label("No Collections", systemImage: "folder")
                    } description: {
                        Text("Create a collection to organize your entries")
                    } actions: {
                        Button("Add Collection") {
                            showingAddCollection = true
                        }
                    }
                }
            }
        }
    }
    
    private func deleteCollection(_ collection: Collection) {
        modelContext.delete(collection)
        collectionToDelete = nil
    }
}

struct CollectionRow: View {
    let collection: Collection
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
                
                Text("\(collection.items.count) entries")
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
        case edit(Collection)
        
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let c): return "edit-\(ObjectIdentifier(c))"
            }
        }
    }
    
    let mode: Mode
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "📁"
    
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
                    Button("Save") {
                        saveCollection()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                if case .edit(let collection) = mode {
                    name = collection.name
                    selectedIcon = collection.icon
                }
            }
        }
    }
    
    private func saveCollection() {
        switch mode {
        case .add:
            let collection = Collection(name: name, icon: selectedIcon)
            modelContext.insert(collection)
        case .edit(let collection):
            collection.name = name
            collection.icon = selectedIcon
        }
        dismiss()
    }
}

#Preview {
    CollectionsView()
        .modelContainer(for: [Collection.self, Item.self], inMemory: true)
}
