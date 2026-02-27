//
//  AddEntryView.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import PhotosUI
import SwiftUI

struct AddEntryView: View {
    enum FocusedField: Hashable { case title, notes }

    @Environment(\.dismiss) private var dismiss

    let collection: CollectionModel

    /// Entry ID to edit (nil for new entry)
    var editingEntryID: String?

    var isEditing: Bool { editingEntryID != nil }

    @State private var types: [EntryTypeModel]

    init(collection: CollectionModel, editingEntryID: String? = nil, initialTypes: [EntryTypeModel] = []) {
        self.collection = collection
        self.editingEntryID = editingEntryID
        self._types = State(initialValue: initialTypes)
    }
    @State private var selectedType: EntryTypeModel?
    @State private var additionalFieldValues: [String: String] = [:]
    @State private var title: String = ""
    @State private var entryDescription: String = ""
    @State private var score: ScoreRating = .undecided
    @State private var date: Date = Date()

    @FocusState private var focus: FocusedField?

    /// Image picker
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []

    /// AI Helper state
    @State private var showAISearchSheet = false
    @State private var errorMessage: String?
    @State private var showError = false

    /// Date picker state
    @State private var showDatePicker = false

    /// Score picker state
    @State private var showScoreSheet = false

    /// Loading states
    @State private var isLoading = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    typePickerSection
                    titleSection
                    additionalFieldsSection
                    notesSection
                    imagesSection
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                    }
                }

                if focus == nil {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(action: { showAISearchSheet = true }) {
                            Image(systemName: "sparkles")
                        }

                        PhotosPicker(
                            selection: $selectedPhotos,
                            maxSelectionCount: 3 - selectedImages.count,
                            matching: .images
                        ) {
                            Image(systemName: "photo")
                        }

                        Spacer()
                    }
                }

                if focus != nil {
                    ToolbarItemGroup(placement: .keyboard) {
                        Button(action: { showAISearchSheet = true }) {
                            Image(systemName: "sparkles")
                        }

                        PhotosPicker(
                            selection: $selectedPhotos,
                            maxSelectionCount: 3 - selectedImages.count,
                            matching: .images
                        ) {
                            Image(systemName: "photo")
                        }

                        Spacer()

                        Button("Done") { focus = nil }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showScoreSheet = true }) {
                        Image(systemName: "star")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showDatePicker = true }) {
                        Image(systemName: "calendar")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        Task {
                            await saveEntry()
                        }
                    }) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(title.isEmpty || isSaving)
                    .buttonStyle(.borderedProminent)
                }
            }
            .onChange(of: selectedPhotos) { _, newValue in
                Task {
                    await loadImages(from: newValue)
                }
            }
            .onChange(of: selectedType) { _, newType in
                let newFieldKeys = Set(newType?.fields.map { $0.key } ?? [])
                additionalFieldValues = additionalFieldValues.filter { newFieldKeys.contains($0.key) }
            }
            .task {
                await loadData()
            }
            .sheet(isPresented: $showAISearchSheet) {
                AISearchBottomSheet(
                    initialQuery: title,
                    onSelect: { option in
                        applyOptionToEntry(option)
                        showAISearchSheet = false
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(date: $date)
                    .presentationDetents([.height(400)])
            }
            .sheet(isPresented: $showScoreSheet) {
                ScoreSelectionSheet(score: $score)
                    .presentationDetents([.height(300)])
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var typePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(types) { type in
                        TypeButton(
                            entryType: type,
                            isSelected: selectedType?.id == type.id
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedType = type
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var titleSection: some View {
        TextField("Title", text: $title)
            .textFieldStyle(.plain)
            .bold()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .focused($focus, equals: .title)
    }

    @ViewBuilder
    private var notesSection: some View {
        ZStack(alignment: .topLeading) {
            if entryDescription.isEmpty {
                Text("Notes, thoughts, review...")
                    .foregroundColor(.secondary)
                    .padding(4)
                    .padding(.top, 4)
            }

            TextEditor(text: $entryDescription)
                .opacity(entryDescription.isEmpty ? 0.25 : 1)
                .contentMargins(.zero)
                .foregroundColor(.primary)
                .padding(.zero)
                .focused($focus, equals: .notes)
        }
        .frame(minHeight: 120)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var additionalFieldsSection: some View {
        if let entryType = selectedType, !entryType.fields.isEmpty {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(entryType.fields, id: \.key) { field in
                    AdditionalFieldCell(field: field, value: fieldBinding(for: field.key))
                }
            }
            .padding(.horizontal)
        }
    }

    private func fieldBinding(for key: String) -> Binding<String> {
        Binding(
            get: { additionalFieldValues[key] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    additionalFieldValues.removeValue(forKey: key)
                } else {
                    additionalFieldValues[key] = newValue
                }
            }
        )
    }

    @ViewBuilder
    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    imagesList
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var imagesList: some View {
        ForEach(Array(selectedImages.enumerated()), id: \.offset) { item in
            ImageThumbnail(
                image: item.element,
                index: item.offset,
                onDelete: {
                    withAnimation {
                        if let i = selectedImages.firstIndex(where: { $0 === item.element }) {
                            _ = selectedImages.remove(at: i)
                        }
                    }
                }
            )
        }
    }

    // MARK: - Helpers

    private func applyOptionToEntry(_ option: AISearchService.EntryOption) {
        title = option.title

        entryDescription = option.description

        // Auto-select type and apply additional fields from AI suggestion
        let entryTypeName: String
        switch option.entryType.lowercased() {
        case "movie": entryTypeName = "Movie"
        case "book": entryTypeName = "Book"
        case "game": entryTypeName = "Game"
        case "show", "tv": entryTypeName = "Show"
        case "music": entryTypeName = "Music"
        default: entryTypeName = ""
        }
        if !entryTypeName.isEmpty, let newType = types.first(where: { $0.name == entryTypeName }) {
            selectedType = newType
            // Preserve existing values, overlay AI suggestions filtered to the new type's fields
            let newFieldKeys = Set(newType.fields.map { $0.key })
            var merged = additionalFieldValues.filter { newFieldKeys.contains($0.key) }
            let aiFields = option.additionalFields
            // TODO: Music type "Artist" key has no matching AI field yet; Year will still be populated.
            for (key, value) in aiFields where newFieldKeys.contains(key) {
                merged[key] = value
            }
            additionalFieldValues = merged
        }

        Task {
            let optionWithImages = await AISearchService.shared.downloadImages(for: option)

            await MainActor.run {
                let images = optionWithImages.downloadedImages.compactMap { UIImage(data: $0) }
                selectedImages = Array(images.prefix(3))
            }
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            types = try await TypeService.shared.getTypes()

            if let entryID = editingEntryID {
                let entry = try await EntryService.shared.getEntry(id: entryID)
                title = entry.title
                entryDescription = entry.description
                score = entry.score
                date = entry.date

                if let typeID = entry.typeID {
                    selectedType = types.first { $0.id == typeID }
                }

                // Load additional fields for editing
                additionalFieldValues = entry.additionalFields

                selectedImages = await loadImages(imageIDs: entry.images)
            }
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
            showError = true
        }

        isLoading = false
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                await MainActor.run {
                    if selectedImages.count < 3 {
                        selectedImages.append(image)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load photo: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
        await MainActor.run {
            selectedPhotos = []
        }
    }

    private func loadImages(imageIDs: [ImageMeta]) async -> [UIImage] {
        typealias TaskResult = (index: Int, image: UIImage?, error: String?)
        let results = await withTaskGroup(of: TaskResult.self) { group in
            for (index, imageMeta) in imageIDs.enumerated() {
                group.addTask {
                    do {
                        let data = try await EntryService.shared.getImage(imageID: imageMeta.id)
                        guard let uiImage = UIImage(data: data) else {
                            return (index, nil, nil)
                        }
                        return (index, uiImage, nil)
                    } catch {
                        return (index, nil, error.localizedDescription)
                    }
                }
            }
            var collected: [TaskResult] = []
            for await result in group { collected.append(result) }
            return collected
        }
        if let msg = results.compactMap({ $0.error }).first {
            errorMessage = "Failed to load image: \(msg)"
            showError = true
        }
        return results.sorted { $0.index < $1.index }.compactMap { $0.image }
    }

    private func saveEntry() async {
        isSaving = true
        errorMessage = nil

        do {
            let imageData = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }

            if let entryID = editingEntryID {
                _ = try await EntryService.shared.updateEntry(
                    id: entryID,
                    collectionID: collection.id,
                    typeID: selectedType?.id,
                    title: title,
                    description: entryDescription,
                    score: score,
                    date: date,
                    additionalFields: additionalFieldValues,
                    imageData: imageData.isEmpty ? nil : imageData
                )
            } else {
                _ = try await EntryService.shared.createEntry(
                    collectionID: collection.id,
                    typeID: selectedType?.id,
                    title: title,
                    description: entryDescription,
                    score: score,
                    date: date,
                    additionalFields: additionalFieldValues,
                    imageData: imageData
                )
            }

            isSaving = false
            dismiss()
        } catch {
            errorMessage = "Failed to save entry: \(error.localizedDescription)"
            showError = true
            isSaving = false
        }
    }
}

// MARK: - Supporting Views

struct AdditionalFieldCell: View {
    let field: FieldDefinition
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: $value)
                .keyboardType(field.isNumber ? .decimalPad : .default)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ImageThumbnail: View {
    let image: UIImage
    let index: Int
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if index == 0 {
                Text("Cover")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(4)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .padding(4)
            .offset(y: index == 0 ? 20 : 0)
        }
    }
}

struct TypeButton: View {
    let entryType: EntryTypeModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(entryType.icon)
                    .font(.title2)
                Text(entryType.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .frame(width: 70)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
    }
}

struct CollectionButton: View {
    let collection: CollectionModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(collection.icon)
                    .font(.title2)
                Text(collection.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .frame(width: 70)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
    }
}

struct ScoreButton: View {
    let rating: ScoreRating
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(rating.emoji)
                    .font(.system(size: 44))
                Text(rating.label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
    }
}

// MARK: - AI Search Bottom Sheet

struct AISearchBottomSheet: View {
    let initialQuery: String
    let onSelect: (AISearchService.EntryOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery: String = ""
    @State private var isSearching = false
    @State private var searchResults: [AISearchService.EntryOption] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showRateLimitAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    TextField("Tell me what you want to discover", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                        .disabled(isSearching)

                    Button(action: isSearching ? stopSearch : startSearch) {
                        Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(isSearching ? Color.red : Color.accentColor)
                            )
                    }
                    .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty && !isSearching)
                }
                .padding(.horizontal)

                if isSearching {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Exploring options…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                if !searchResults.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(searchResults) { option in
                                AIHelperOptionCard(option: option) {
                                    onSelect(option)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("AI Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        stopSearch()
                        dismiss()
                    }
                }
            }
            .onAppear {
                searchQuery = initialQuery
            }
            .onDisappear {
                stopSearch()
            }
            .alert("Daily Limit Reached", isPresented: $showRateLimitAlert) {
                Button("OK") {
                    showRateLimitAlert = false
                }
            } message: {
                Text("You have exceeded your daily AI search limit. Please try again tomorrow.")
            }
        }
    }

    private func startSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isSearching = true
        errorMessage = nil
        searchResults = []

        searchTask = Task {
            do {
                let options = try await AISearchService.shared.searchOptions(for: searchQuery)

                if Task.isCancelled { return }

                await MainActor.run {
                    isSearching = false
                    if options.isEmpty {
                        errorMessage = "Nothing found, try a different search"
                    } else {
                        searchResults = Array(options.prefix(5))
                    }
                }
            } catch {
                if Task.isCancelled { return }

                await MainActor.run {
                    isSearching = false

                    if let aiError = error as? AISearchError,
                       case .rateLimitExceeded = aiError {
                        showRateLimitAlert = true
                        errorMessage = nil
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
}

struct AIHelperOptionCard: View {
    let option: AISearchService.EntryOption
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .overlay {
                        if let firstImageUrl = option.imageUrls.first,
                           let url = URL(string: firstImageUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure, .empty:
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(option.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if let year = option.year {
                            Text("(\(year))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let genre = option.genre {
                        Text(genre)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let author = option.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let platform = option.platform {
                        Text(platform)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DatePickerSheet: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "Entry date",
                    selection: $date,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.all, 12)

                Spacer()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ScoreSelectionSheet: View {
    @Binding var score: ScoreRating
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(score.emoji)
                        .font(.system(size: 64))
                    Text(score.label)
                        .font(.headline)
                        .foregroundStyle(score == .undecided ? .secondary : .primary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 110)
                .padding(.top, 8)

                HStack(spacing: 16) {
                    ForEach(ScoreRating.allCases) { rating in
                        ScoreOptionButton(
                            rating: rating,
                            isSelected: score == rating
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                score = rating
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("What's the verdict?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct ScoreOptionButton: View {
    let rating: ScoreRating
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(rating.emoji)
                .font(.system(size: 44))
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.1 : 1.0)
    }
}

#Preview {
    AddEntryView(collection: CollectionModel.previewMyList, initialTypes: EntryTypeModel.previewTypes)
}
