//
//  CollectionsView.swift
//  livlogios
//
//  Created by avprokopev on 14.01.2026.
//

import SwiftUI

struct CollectionsView: View {
    @State private var collections: [CollectionModel] = []
    @State private var showingAddCollection = false
    @State private var editingCollection: CollectionModel?
    @State private var showingDeleteAlert = false
    @State private var collectionToDelete: CollectionModel?
    @State private var sharingCollection: CollectionModel?

    @State private var isLoading = false
    @State private var isCreatingDefaults = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    List {
                        ForEach(collections) { collection in
                            NavigationLink {
                                ContentView(collection: collection)
                            } label: {
                                CollectionRow(
                                    collection: collection,
                                    entryCount: collection.entryCount,
                                    onEdit: { editingCollection = collection },
                                    onShare: { sharingCollection = collection },
                                    onDelete: {
                                        collectionToDelete = collection
                                        showingDeleteAlert = true
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("My Collections")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
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
            .sheet(item: $sharingCollection) { collection in
                ShareCollectionSheet(collection: collection)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .alert("Leave Collection", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    collectionToDelete = nil
                }
                Button("Leave", role: .destructive) {
                    if let collection = collectionToDelete {
                        Task {
                            await deleteCollection(collection)
                        }
                    }
                }
            } message: {
                if let collection = collectionToDelete {
                    let otherMembers = collection.memberCount - 1
                    if otherMembers > 0 {
                        Text("Leave \"\(collection.name)\"? The collection will remain accessible to \(otherMembers) other member\(otherMembers == 1 ? "" : "s").")
                    } else {
                        Text("Leave \"\(collection.name)\"? You are the only member — the collection will become inaccessible.")
                    }
                }
            }
            .overlay {
                if collections.isEmpty && !isLoading {
                    ContentUnavailableView {
                        Label("No Collections", systemImage: "folder")
                    } description: {
                        Text("Create a collection to organize your entries")
                    } actions: {
                        Button {
                            Task {
                                await createDefaultCollections()
                            }
                        } label: {
                            if isCreatingDefaults {
                                ProgressView()
                            } else {
                                Text("Create My List")
                            }
                        }
                        .disabled(isCreatingDefaults)
                        .buttonStyle(.borderedProminent)
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
        do {
            collections = try await CollectionService.shared.getCollections()
        } catch {
            errorMessage = error.localizedDescription
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
            errorMessage = "Failed to leave collection: \(error.localizedDescription)"
            showError = true
        }

        collectionToDelete = nil
    }
}

struct CollectionRow: View {
    let collection: CollectionModel
    let entryCount: Int
    let onEdit: () -> Void
    let onShare: () -> Void
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
                Label("Leave", systemImage: "trash")
            }

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)

            if collection.myRole.canEdit {
                Button(action: onShare) {
                    Label("Share", systemImage: "person.2")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }

            if collection.myRole.canEdit {
                Button(action: onShare) {
                    Label("Share", systemImage: "person.badge.plus")
                }
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
            }
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
    @EnvironmentObject private var appState: AppState

    @State private var name: String = ""
    @State private var selectedIcon: String = "📁"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    // Members section state (edit mode only)
    @State private var members: [CollectionMember] = []
    @State private var isLoadingMembers = false
    @State private var memberToRemove: CollectionMember?
    @State private var showingRemoveMemberAlert = false
    @State private var showingAddMember = false

    private let emojiOptions = [
        "📁", "🎬", "📚", "🎮", "🎵", "🎨", "🍿", "📺", "🎭", "🎪",
        "✈️", "🌍", "🍽️", "☕️", "🏋️", "⚽️", "🎾", "🎯", "🎲", "🎸",
        "📷", "💼", "🎓", "💡", "🔧", "🛠️", "🎁", "💎", "🌟", "✨"
    ]

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingCollection: CollectionModel? {
        if case .edit(let c) = mode { return c }
        return nil
    }

    private var isOwner: Bool {
        editingCollection?.myRole.canEdit ?? true
    }

    private var title: String {
        isEditing ? "Edit Collection" : "New Collection"
    }

    var body: some View {
        NavigationStack {
            Form {
                if isEditing && !isOwner {
                    Section {
                        Label(
                            "You have view-only access to this collection. Ask an owner to make changes.",
                            systemImage: "lock"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Name") {
                    TextField("Collection name", text: $name)
                        .disabled(isEditing && !isOwner)
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
                            .disabled(isEditing && !isOwner)
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

                if isEditing && isOwner {
                    membersSection
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

                if isOwner {
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
            }
            .onAppear {
                if case .edit(let collection) = mode {
                    name = collection.name
                    selectedIcon = collection.icon
                }
            }
            .task {
                if isEditing && isOwner, let collection = editingCollection {
                    await loadMembers(collectionID: collection.id)
                }
            }
            .sheet(isPresented: $showingAddMember) {
                if let collection = editingCollection {
                    ShareCollectionSheet(collection: collection) {
                        Task {
                            await loadMembers(collectionID: collection.id)
                        }
                    }
                }
            }
            .alert("Remove Member", isPresented: $showingRemoveMemberAlert) {
                Button("Cancel", role: .cancel) {
                    memberToRemove = nil
                }
                Button("Remove", role: .destructive) {
                    if let member = memberToRemove, let collection = editingCollection {
                        Task {
                            await removeMember(member, collectionID: collection.id)
                        }
                    }
                }
            } message: {
                if let member = memberToRemove {
                    let name = member.displayName ?? member.email ?? member.userId
                    Text("Remove \"\(name)\" from this collection?")
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

    @ViewBuilder
    private var membersSection: some View {
        Section("Members") {
            if isLoadingMembers {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                ForEach(members) { member in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if let displayName = member.displayName, !displayName.isEmpty {
                                Text(displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let email = member.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else if let email = member.email {
                                Text(email)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            } else {
                                Text(member.userId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Text(member.role.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(roleBadgeColor(member.role).opacity(0.15))
                            .foregroundStyle(roleBadgeColor(member.role))
                            .clipShape(Capsule())

                        let currentUserID = appState.currentUser?.id.uuidString
                        if member.userId != currentUserID {
                            Button {
                                memberToRemove = member
                                showingRemoveMemberAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Button {
                    showingAddMember = true
                } label: {
                    Label("Add Member", systemImage: "person.badge.plus")
                }
            }
        }
    }

    private func roleBadgeColor(_ role: CollectionRole) -> Color {
        switch role {
        case .owner: return .orange
        case .write: return .blue
        case .read: return .secondary
        }
    }

    private func loadMembers(collectionID: String) async {
        isLoadingMembers = true
        do {
            members = try await CollectionService.shared.getMembers(collectionID: collectionID)
        } catch {
            errorMessage = "Failed to load members: \(error.localizedDescription)"
            showError = true
        }
        isLoadingMembers = false
    }

    private func removeMember(_ member: CollectionMember, collectionID: String) async {
        do {
            try await CollectionService.shared.removeShare(collectionID: collectionID, userID: member.userId)
            await loadMembers(collectionID: collectionID)
        } catch {
            errorMessage = "Failed to remove member: \(error.localizedDescription)"
            showError = true
        }
        memberToRemove = nil
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

struct ShareCollectionSheet: View {
    let collection: CollectionModel
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role: CollectionRole = .read
    @State private var isSharing = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Email Address") {
                    TextField("colleague@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }

                Section("Permission") {
                    Picker("Role", selection: $role) {
                        Text("Reader (read only)").tag(CollectionRole.read)
                        Text("Writer (can add entries)").tag(CollectionRole.write)
                        Text("Owner (full control)").tag(CollectionRole.owner)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Button {
                        Task { await shareCollection() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSharing {
                                ProgressView()
                            } else {
                                Label("Share", systemImage: "person.badge.plus")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isEmailValid || isSharing)

                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .navigationTitle("Share Collection")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Shared!", isPresented: $showSuccess) {
                Button("OK") {
                    onDone?()
                    dismiss()
                }
            } message: {
                Text("\(email) has been added to \"\(collection.name)\".")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
        }
    }

    private func shareCollection() async {
        isSharing = true
        do {
            try await CollectionService.shared.addShare(
                collectionID: collection.id,
                email: email,
                role: role
            )
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isSharing = false
    }
}

#Preview {
    CollectionsView()
}
