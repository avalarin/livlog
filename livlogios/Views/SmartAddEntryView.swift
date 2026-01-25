//
//  SmartAddEntryView.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import SwiftUI
import SwiftData

struct SmartAddEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Collection.createdAt) private var collections: [Collection]
    
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var isDownloadingImages = false
    @State private var options: [OpenAIService.EntryOption] = []
    @State private var selectedOption: OpenAIService.EntryOption?
    @State private var errorMessage: String?
    @State private var showingManualEntry = false
    
    // For selected option - editable fields
    @State private var selectedCollection: Collection?
    @State private var score: ScoreRating = .okay
    @State private var date: Date = Date()
    @State private var notes: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if selectedOption == nil {
                    searchSection
                } else {
                    confirmationSection
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                if selectedOption != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveEntry()
                        }
                        .fontWeight(.semibold)
                        .disabled(isDownloadingImages)
                    }
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                AddEntryView()
            }
            .onAppear {
                // Auto-select first collection
                if selectedCollection == nil, let first = collections.first {
                    selectedCollection = first
                }
            }
        }
    }
    
    // MARK: - Search Section
    
    @ViewBuilder
    private var searchSection: some View {
        VStack(spacing: 24) {
            searchInputSection
            searchButtonSection
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            
            if !options.isEmpty {
                resultsSection
            } else if !isSearching && searchQuery.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private var searchInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What did you watch, read, or play?")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Enter title...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        options = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
        .padding(.horizontal)
        .padding(.top)
    }
    
    @ViewBuilder
    private var searchButtonSection: some View {
        Button {
            performSearch()
        } label: {
            HStack {
                if isSearching {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(isSearching ? "Searching..." : "Search with AI")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(searchQuery.isEmpty ? Color.gray : Color.accentColor)
            )
            .foregroundStyle(.white)
            .fontWeight(.semibold)
        }
        .disabled(searchQuery.isEmpty || isSearching)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("AI-Powered Search")
                .font(.headline)
            
            Text("Enter a title and we'll find details\nabout movies, books, and games for you")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingManualEntry = true
            } label: {
                Text("Or add manually")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select an option")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(options) { option in
                        OptionCard(option: option, collections: collections) {
                            selectOption(option)
                        }
                    }
                    
                    manualEntryButton
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private var manualEntryButton: some View {
        Button {
            showingManualEntry = true
        } label: {
            HStack {
                Image(systemName: "pencil")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Not what you're looking for?")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Add entry manually")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Confirmation Section
    
    @ViewBuilder
    private var confirmationSection: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let option = selectedOption {
                    optionPreviewSection(option: option)
                }
                
                collectionPickerSection
                scorePickerSection
                datePickerSection
                notesSection
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var collectionPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collection")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(collections) { collection in
                        Button {
                            selectedCollection = collection
                        } label: {
                            HStack(spacing: 6) {
                                Text(collection.icon)
                                Text(collection.name)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedCollection?.id == collection.id ? Color.accentColor : Color(.systemGray6))
                            )
                            .foregroundStyle(selectedCollection?.id == collection.id ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button {
                        selectedCollection = nil
                    } label: {
                        HStack(spacing: 6) {
                            Text("📝")
                            Text("None")
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedCollection == nil ? Color.accentColor : Color(.systemGray6))
                        )
                        .foregroundStyle(selectedCollection == nil ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    @ViewBuilder
    private func optionPreviewSection(option: OpenAIService.EntryOption) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    withAnimation {
                        selectedOption = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .foregroundStyle(Color.accentColor)
                
                Spacer()
                
                if isDownloadingImages {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading images...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Images preview
            if !option.downloadedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(option.downloadedImages.enumerated()), id: \.offset) { index, imageData in
                            if let uiImage = UIImage(data: imageData) {
                                ZStack(alignment: .topLeading) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
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
                                }
                            }
                        }
                    }
                }
            }
            
            // Entry info
            HStack(alignment: .top, spacing: 16) {
                Text(option.suggestedIcon)
                    .font(.system(size: 44))
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 8) {
                        Text(option.entryType.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                        
                        if let year = option.year {
                            Text(year)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if let genre = option.genre {
                        Text(genre)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Text(option.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
    
    @ViewBuilder
    private var scorePickerSection: some View {
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
                        withAnimation {
                            score = rating
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var datePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("When?")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
        }
    }
    
    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes (optional)")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            TextField("Your thoughts...", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
        }
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        options = []
        
        Task {
            do {
                let results = try await OpenAIService.searchOptions(for: searchQuery)
                await MainActor.run {
                    options = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }
    
    private func selectOption(_ option: OpenAIService.EntryOption) {
        selectedOption = option
        
        // Auto-select matching collection based on entry type
        let typeLower = option.entryType.lowercased()
        if let matchingCollection = collections.first(where: { $0.name.lowercased().contains(typeLower) || typeLower.contains($0.name.lowercased()) }) {
            selectedCollection = matchingCollection
        }
        
        // Download images in background
        isDownloadingImages = true
        Task {
            let optionWithImages = await OpenAIService.downloadImages(for: option)
            await MainActor.run {
                selectedOption = optionWithImages
                isDownloadingImages = false
            }
        }
    }
    
    private func saveEntry() {
        guard let option = selectedOption else { return }
        
        let newItem = Item(
            collection: selectedCollection,
            title: option.title,
            entryDescription: notes.isEmpty ? option.description : notes,
            score: score,
            date: date,
            additionalFields: option.additionalFields,
            images: option.downloadedImages
        )
        
        modelContext.insert(newItem)
        dismiss()
    }
}

// MARK: - Option Card

struct OptionCard: View {
    let option: OpenAIService.EntryOption
    let collections: [Collection]
    let onSelect: () -> Void
    
    private var suggestedCollection: Collection? {
        let typeLower = option.entryType.lowercased()
        return collections.first { $0.name.lowercased().contains(typeLower) || typeLower.contains($0.name.lowercased()) }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Text(option.suggestedIcon)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                    
                    HStack(spacing: 8) {
                        if let collection = suggestedCollection {
                            HStack(spacing: 4) {
                                Text(collection.icon)
                                Text(collection.name)
                            }
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                        } else {
                            Text(option.entryType.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        
                        if let year = option.year {
                            Text(year)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let genre = option.genre {
                            Text(genre)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SmartAddEntryView()
        .modelContainer(for: [Collection.self, Item.self], inMemory: true)
}
