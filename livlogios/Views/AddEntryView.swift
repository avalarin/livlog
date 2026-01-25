//
//  AddEntryView.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    
    /// Item to edit (nil for new entry)
    var editingItem: Item?
    
    var isEditing: Bool { editingItem != nil }
    
    @State private var selectedCollection: Collection?
    @State private var title: String = ""
    @State private var entryDescription: String = ""
    @State private var score: ScoreRating = .okay
    @State private var date: Date = Date()
    
    /// Dynamic additional fields storage
    @State private var fieldValues: [String: String] = [:]
    
    /// Image picker
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    collectionPickerSection
                    titleSection
                    additionalFieldsSection
                    imagesSection
                    notesSection
                    scoreSection
                    dateSection
                }
                .padding(.vertical)
            }
            .navigationTitle(isEditing ? "Edit Entry" : "New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.isEmpty)
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
        }
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private var collectionPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collection")
                .font(.headline)
                .foregroundStyle(.secondary)
            
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
                    
                    // "No Collection" option
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedCollection = nil
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text("📝")
                                .font(.title2)
                            Text("None")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .frame(width: 70)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedCollection == nil ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedCollection == nil ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Title")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            TextField("What's it called?", text: $title)
                .textFieldStyle(.plain)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            TextField("Your thoughts...", text: $entryDescription, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How was it?")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                ForEach(ScoreRating.allCases) { rating in
                    ScoreButton(
                        rating: rating,
                        isSelected: score == rating
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            score = rating
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When?")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            DatePicker(
                "Date",
                selection: $date,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var additionalFieldsSection: some View {
        VStack(spacing: 16) {
            DynamicFieldInput(
                fieldName: "Year",
                value: binding(for: "Year")
            )
            DynamicFieldInput(
                fieldName: "Genre",
                value: binding(for: "Genre")
            )
            DynamicFieldInput(
                fieldName: "Author",
                value: binding(for: "Author")
            )
            DynamicFieldInput(
                fieldName: "Platform",
                value: binding(for: "Platform")
            )
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var imagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Images")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(selectedImages.count)/3")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    addPhotoButton
                    imagesList
                }
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var addPhotoButton: some View {
        if selectedImages.count < 3 {
            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 3 - selectedImages.count,
                matching: .images
            ) {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Add")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 100, height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .strokeBorder(Color(.systemGray4), style: StrokeStyle(lineWidth: 2, dash: [6]))
                )
            }
        }
    }
    
    @ViewBuilder
    private var imagesList: some View {
        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
            ImageThumbnail(
                image: image,
                index: index,
                onDelete: {
                    withAnimation {
                        let _ = selectedImages.remove(at: index)
                    }
                }
            )
        }
    }
    
    // MARK: - Helpers
    
    private func binding(for fieldName: String) -> Binding<String> {
        Binding(
            get: { fieldValues[fieldName] ?? "" },
            set: { fieldValues[fieldName] = $0 }
        )
    }
    
    private func loadItemData(_ item: Item) {
        selectedCollection = item.collection
        title = item.title
        entryDescription = item.entryDescription
        score = item.score
        date = item.date
        fieldValues = item.additionalFields
        selectedImages = item.images.compactMap { UIImage(data: $0) }
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
        let filledFields = fieldValues.filter { !$0.value.isEmpty }
        let imageData = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
        
        if let item = editingItem {
            item.collection = selectedCollection
            item.title = title
            item.entryDescription = entryDescription
            item.score = score
            item.date = date
            item.additionalFields = filledFields
            item.images = imageData
        } else {
            let newItem = Item(
                collection: selectedCollection,
                title: title,
                entryDescription: entryDescription,
                score: score,
                date: date,
                additionalFields: filledFields,
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

struct DynamicFieldInput: View {
    let fieldName: String
    @Binding var value: String
    
    private var placeholder: String {
        switch fieldName {
        case "Year": return "2024"
        case "Genre": return "Action, Drama..."
        case "Author": return "Who wrote it?"
        case "Platform": return "PC, PlayStation, Xbox..."
        default: return "Enter \(fieldName.lowercased())"
        }
    }
    
    private var keyboardType: UIKeyboardType {
        fieldName == "Year" ? .numberPad : .default
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fieldName)
                .font(.headline)
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: $value)
                .textFieldStyle(.plain)
                .keyboardType(keyboardType)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
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
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
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

#Preview {
    AddEntryView()
        .modelContainer(for: [Collection.self, Item.self], inMemory: true)
}
