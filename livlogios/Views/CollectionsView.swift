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
            .refreshable {
                await loadData()
            }
            .overlay {
                if collections.isEmpty && isLoading {
                    ProgressView()
                }
            }
            .navigationTitle("Grove Lists")
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
                ShareCollectionSheet(collection: collection) {
                    Task { await loadData() }
                }
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
                    let otherMembers = max(0, collection.memberCount - 1)
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
        defer { isLoading = false }
        do {
            collections = try await CollectionService.shared.getCollections()
       } catch is CancellationError {
           return
       } catch let urlError as URLError where urlError.code == .cancelled {
           return
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
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
            CollectionIconView(iconRaw: collection.icon, colorRaw: collection.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.headline)

                HStack(spacing: 6) {
                    Text("\(entryCount) \(entryCount == 1 ? "entry" : "entries")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if collection.myRole == .read {
                        Text("· Read Only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let sharedBy = collection.sharedBy {
                    Text("Shared by \(sharedBy)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Leave", systemImage: "trash")
            }

            if collection.myRole.canEdit {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.orange)

                Button(action: onShare) {
                    Label("Share", systemImage: "person.2")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if collection.myRole.canEdit {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }

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
            case .edit(let collection): return "edit-\(collection.id)"
            }
        }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var name: String = ""
    @State private var selectedIcon: CollectionIcon = .system("folder")
    @State private var selectedColor: CollectionColor = .dodgerBlue
    @State private var iconTab: IconTab = .system
    @State private var emojiText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    // Members section state (edit mode only)
    @State private var members: [CollectionMember] = []
    @State private var isLoadingMembers = false
    @State private var selectedMember: CollectionMember?
    @State private var showingAddMember = false

    enum IconTab: String, CaseIterable {
        case system = "Icons"
        case emoji = "Emoji"
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingCollection: CollectionModel? {
        if case .edit(let collection) = mode { return collection }
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
                    Picker("", selection: $iconTab) {
                        ForEach(IconTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isEditing && !isOwner)

                    if iconTab == .system {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(CollectionIcon.allSystemIcons, id: \.self) { iconName in
                                let isSelected = selectedIcon == .system(iconName)
                                Button {
                                    selectedIcon = .system(iconName)
                                } label: {
                                    Image(iconName)
                                        .renderingMode(.template)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(selectedColor.color)
                                        .padding(8)
                                        .frame(width: 44, height: 44)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(isSelected ? selectedColor.color.opacity(0.2) : Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? selectedColor.color : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                                .disabled(isEditing && !isOwner)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        TextField("Enter emoji", text: $emojiText)
                            .font(.title)
                            .multilineTextAlignment(.center)
                            .onChange(of: emojiText) { _, newValue in
                                if !newValue.isEmpty {
                                    let trimmed = String(newValue.prefix(1))
                                    if trimmed != newValue {
                                        emojiText = trimmed
                                    }
                                    selectedIcon = .emoji(trimmed)
                                }
                            }
                            .disabled(isEditing && !isOwner)
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(CollectionColor.allCases, id: \.self) { colorOption in
                            Button {
                                selectedColor = colorOption
                            } label: {
                                Circle()
                                    .fill(colorOption.color)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if selectedColor == colorOption {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
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
                            CollectionIconView(icon: selectedIcon, color: selectedColor, size: 32)
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
                    let parsed = CollectionIcon(raw: collection.icon)
                    selectedIcon = parsed
                    selectedColor = CollectionColor(rawValue: collection.color) ?? .dodgerBlue
                    switch parsed {
                    case .system:
                        iconTab = .system
                    case .emoji(let emoji):
                        iconTab = .emoji
                        emojiText = emoji
                    }
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
            .sheet(item: $selectedMember) { member in
                if let collection = editingCollection {
                    EditMemberSheet(collection: collection, member: member) {
                        Task {
                            await loadMembers(collectionID: collection.id)
                        }
                    }
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
                let currentUserID = appState.currentUser?.id.uuidString.lowercased()
                ForEach(members) { member in
                    let isSelf = member.userId.lowercased() == currentUserID
                    let isTappable = isOwner && !isSelf
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

                        if isTappable {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isTappable {
                            selectedMember = member
                        }
                    }
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
        defer { isLoadingMembers = false }
        do {
            members = try await CollectionService.shared.getMembers(collectionID: collectionID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Failed to load members: \(error.localizedDescription)"
            showError = true
        }
    }

    private func saveCollection() async {
        isSaving = true
        errorMessage = nil

        do {
            let iconRaw = selectedIcon.rawValue
            let colorRaw = selectedColor.rawValue
            switch mode {
            case .add:
                _ = try await CollectionService.shared.createCollection(name: name, icon: iconRaw, color: colorRaw)
            case .edit(let collection):
                _ = try await CollectionService.shared.updateCollection(id: collection.id, name: name, icon: iconRaw, color: colorRaw)
            }
            isSaving = false
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
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role: CollectionRole = .read
    @State private var isSharing = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var isEmailValid: Bool {
        let pattern = #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Email Address") {
                    TextField("friend@example.com", text: $email)
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
                }
            }
            .navigationTitle("Share Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
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

struct EditMemberSheet: View {
    let collection: CollectionModel
    let member: CollectionMember
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var role: CollectionRole
    @State private var isSaving = false
    @State private var isRevoking = false
    @State private var showRevokeConfirmation = false
    @State private var errorMessage: String?
    @State private var showError = false

    init(collection: CollectionModel, member: CollectionMember, onDone: (() -> Void)? = nil) {
        self.collection = collection
        self.member = member
        self.onDone = onDone
        _role = State(initialValue: member.role)
    }

    private var hasChanges: Bool {
        role != member.role
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Member") {
                    if let displayName = member.displayName, !displayName.isEmpty {
                        LabeledContent("Name", value: displayName)
                    }
                    if let email = member.email {
                        LabeledContent("Email", value: email)
                    }
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
                    Button(role: .destructive) {
                        showRevokeConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if isRevoking {
                                ProgressView()
                            } else {
                                Label("Revoke Access", systemImage: "person.badge.minus")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSaving || isRevoking)
                }
            }
            .navigationTitle("Edit Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveRole() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!hasChanges || isSaving || isRevoking)
                }
            }
            .alert("Revoke Access", isPresented: $showRevokeConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Revoke", role: .destructive) {
                    Task { await revokeAccess() }
                }
            } message: {
                let identifier = member.email ?? member.userId
                Text("Are you sure you want to remove \"\(collection.name)\" from \(identifier)?")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
        }
    }

    private func saveRole() async {
        isSaving = true
        do {
            try await CollectionService.shared.updateShare(
                collectionID: collection.id,
                userID: member.userId,
                role: role
            )
            onDone?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isSaving = false
    }

    private func revokeAccess() async {
        isRevoking = true
        do {
            try await CollectionService.shared.removeShare(
                collectionID: collection.id,
                userID: member.userId
            )
            onDone?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isRevoking = false
    }
}

#Preview {
    CollectionsView()
}

#Preview("Share Collection") {
    NavigationStack {
        ShareCollectionSheet(collection: CollectionModel(id: "", name: "Preview", icon: "system:folder"))
    }
}
