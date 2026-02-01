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

    /// Entry ID to edit (nil for new entry)
    var editingEntryID: String?

    var isEditing: Bool { editingEntryID != nil }

    @State private var collections: [CollectionModel] = []
    @State private var selectedCollection: CollectionModel?
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
                VStack(spacing: 24) {
                    collectionPickerSection
                    textSection
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
    private var collectionPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(collections) { collection in
                        CollectionButton(
                            collection: collection,
                            isSelected: selectedCollection?.id == collection.id
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedCollection = collection
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var textSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .bold()
                .padding(.horizontal, 12)
                .focused($focus, equals: .title)
            
            ZStack(alignment: .topLeading) {
                if true {
                    Text("Details, e.g. year, genre...")
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
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8)
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
        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
            ImageThumbnail(
                image: image,
                index: index,
                onDelete: {
                    withAnimation {
                        _ = selectedImages.remove(at: index)
                    }
                }
            )
        }
    }
    
    // MARK: - Helpers

    private func applyOptionToEntry(_ option: AISearchService.EntryOption) {
        // Set title
        title = option.title

        // Format notes: summary line first, then description
        var notesText = ""

        // Add summary line (generated by LLM based on content type)
        if !option.summaryLine.isEmpty {
            notesText = option.summaryLine + "\n"
        }

        // Add description
        notesText += option.description
        entryDescription = notesText

        // Download and apply images
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
            // Load collections
            collections = try await CollectionService.shared.getCollections()

            // If editing, load the entry
            if let entryID = editingEntryID {
                let entry = try await EntryService.shared.getEntry(id: entryID)
                title = entry.title
                entryDescription = entry.description
                score = entry.score
                date = entry.date

                if let collectionID = entry.collectionID {
                    selectedCollection = collections.first { $0.id == collectionID }
                }

                // Load images
                let entryImages = try await EntryService.shared.getEntryImages(entryID: entryID)
                let sortedImages = entryImages.sorted { $0.position < $1.position }
                selectedImages = sortedImages.compactMap { imageModel in
                    guard let data = Data(base64Encoded: imageModel.data),
                          let uiImage = UIImage(data: data) else {
                        return nil
                    }
                    return uiImage
                }
            } else {
                // New entry: select first collection
                if selectedCollection == nil {
                    selectedCollection = collections.first
                }
            }
        } catch {
            errorMessage = "Failed to load data: \(error.localizedDescription)"
            showError = true
        }

        isLoading = false
    }
    
    private func loadImages(from items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    if selectedImages.count < 3 {
                        selectedImages.append(image)
                    }
                }
            }
        }
        await MainActor.run {
            selectedPhotos = []
        }
    }
    
    private func saveEntry() async {
        isSaving = true
        errorMessage = nil

        do {
            let imageData = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }

            if let entryID = editingEntryID {
                // Update existing entry
                _ = try await EntryService.shared.updateEntry(
                    id: entryID,
                    collectionID: selectedCollection?.id,
                    title: title,
                    description: entryDescription,
                    score: score,
                    date: date,
                    additionalFields: [:],
                    imageData: imageData.isEmpty ? nil : imageData
                )
            } else {
                // Create new entry
                _ = try await EntryService.shared.createEntry(
                    collectionID: selectedCollection?.id,
                    title: title,
                    description: entryDescription,
                    score: score,
                    date: date,
                    additionalFields: [:],
                    imageData: imageData
                )
            }

            dismiss()
        } catch {
            errorMessage = "Failed to save entry: \(error.localizedDescription)"
            showError = true
            isSaving = false
        }
    }
}

// MARK: - Supporting Views

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
                // Search field
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

                // Loading state
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

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Results
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

                    // Check for rate limit error
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
                // Preview image placeholder
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
                    // Title and year
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

                    // Genre/Author
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

                    // Short description
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
                // Current selection display
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

                // Score options
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
    AddEntryView()
}
