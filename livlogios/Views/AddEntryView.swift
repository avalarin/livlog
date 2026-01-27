//
//  AddEntryView.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import PhotosUI
import SwiftData
import SwiftUI

struct AddEntryView: View {
    enum FocusedField: Hashable { case title, notes }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    
    /// Item to edit (nil for new entry)
    var editingItem: Item?
    
    var isEditing: Bool { editingItem != nil }
    
    @State private var selectedCollection: Collection?
    @State private var title: String = ""
    @State private var entryDescription: String = ""
    @State private var score: ScoreRating = .undecided
    @State private var date: Date = Date()

    @FocusState private var focus: FocusedField?
    
    /// Image picker
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []

    /// AI Helper state
    @State private var isLoadingOptions = false
    @State private var showOptionsSheet = false
    @State private var foundOptions: [OpenAIService.EntryOption] = []
    @State private var errorMessage: String?
    @State private var showError = false

    /// Date picker state
    @State private var showDatePicker = false

    /// Score picker state
    @State private var showScoreSheet = false
    
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
                        Button(action: searchWithAI) {
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
                        Button(action: searchWithAI) {
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
                    Button(action: { saveEntry() }) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .disabled(title.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
            .onChange(of: selectedPhotos) { _, newValue in
                Task {
                    await loadImages(from: newValue)
                }
            }
            .onAppear {
                if let item = editingItem {
                    loadItemData(item)
                } else if selectedCollection == nil, let first = collections.first {
                    selectedCollection = first
                }
            }
            .sheet(isPresented: $isLoadingOptions) {
                LoadingSheet()
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showOptionsSheet) {
                OptionsSelectionSheet(
                    options: foundOptions,
                    onSelect: { option in
                        applyOptionToEntry(option)
                        showOptionsSheet = false
                    },
                    onCancel: {
                        showOptionsSheet = false
                    }
                )
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

    private var canUseAIHelper: Bool {
        selectedCollection != nil && title.count >= 2
    }

    private func searchWithAI() {
        guard canUseAIHelper else { return }

        isLoadingOptions = true
        foundOptions = []

        Task {
            do {
                let options = try await OpenAIService.searchOptions(for: title)

                await MainActor.run {
                    isLoadingOptions = false

                    if options.isEmpty {
                        errorMessage = "Ничего не найдено, попробуйте другое название"
                        showError = true
                    } else {
                        foundOptions = options
                        showOptionsSheet = true
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingOptions = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func applyOptionToEntry(_ option: OpenAIService.EntryOption) {
        // Format notes: first line metadata, then description
        var notesText = ""

        // Add metadata to first line
        if !option.additionalFields.isEmpty {
            let fieldsArray = option.additionalFields
                .sorted { $0.key < $1.key }
                .map { $0.value }
            notesText = fieldsArray.joined(separator: ", ") + "\n"
        }

        // Add description
        notesText += option.description
        entryDescription = notesText

        // Download and apply images
        Task {
            let optionWithImages = await OpenAIService.downloadImages(for: option)

            await MainActor.run {
                let images = optionWithImages.downloadedImages.compactMap { UIImage(data: $0) }
                selectedImages = Array(images.prefix(3))
            }
        }
    }
    
    private func loadItemData(_ item: Item) {
        selectedCollection = item.collection
        title = item.title
        score = item.score
        date = item.date
        selectedImages = item.images.compactMap { UIImage(data: $0) }

        // Migrate additionalFields to notes if needed
        if !item.additionalFields.isEmpty && item.entryDescription.isEmpty {
            let fieldsString = item.additionalFields
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            entryDescription = fieldsString
        } else if !item.additionalFields.isEmpty {
            // If notes already exist, prepend fields
            let fieldsString = item.additionalFields
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            entryDescription = "\(fieldsString)\n\(item.entryDescription)"
        } else {
            entryDescription = item.entryDescription
        }
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
    
    private func saveEntry() {
        let imageData = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }

        if let item = editingItem {
            item.collection = selectedCollection
            item.title = title
            item.entryDescription = entryDescription
            item.score = score
            item.date = date
            item.additionalFields = [:] // Clear old additionalFields
            item.images = imageData
        } else {
            let newItem = Item(
                collection: selectedCollection,
                title: title,
                entryDescription: entryDescription,
                score: score,
                date: date,
                additionalFields: [:],
                images: imageData
            )
            modelContext.insert(newItem)
        }
        dismiss()
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
    let collection: Collection
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

// MARK: - AI Helper Views

struct LoadingSheet: View {
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Ищу варианты...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct OptionsSelectionSheet: View {
    let options: [OpenAIService.EntryOption]
    let onSelect: (OpenAIService.EntryOption) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(options) { option in
                        AIHelperOptionCard(option: option) {
                            onSelect(option)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Выберите вариант")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        onCancel()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AIHelperOptionCard: View {
    let option: OpenAIService.EntryOption
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
                .padding()

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
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Collection.self, Item.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )

    // Add default collections
    for (name, icon) in Collection.defaultCollections {
        container.mainContext.insert(Collection(name: name, icon: icon))
    }

    return AddEntryView()
        .modelContainer(container)
}
