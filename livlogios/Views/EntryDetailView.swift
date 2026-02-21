//
//  EntryDetailView.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import SwiftUI

struct EntryDetailView: View {
    let entryID: String

    @Environment(\.dismiss) private var dismiss

    @State private var entry: EntryModel?
    @State private var collection: CollectionModel?
    @State private var images: [UIImage] = []

    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    @State private var selectedImageIndex: Int = 0

    @State private var isLoading = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var metadataItems: [(key: String, value: String)] {
        guard let entry = entry else { return [] }
        let fieldOrder = ["Year", "Genre", "Author", "Platform"]
        return entry.additionalFields.sorted { a, b in
            let indexA = fieldOrder.firstIndex(of: a.key) ?? Int.max
            let indexB = fieldOrder.firstIndex(of: b.key) ?? Int.max
            return indexA < indexB
        }
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let entry = entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Image Gallery
                        if !images.isEmpty {
                            TabView(selection: $selectedImageIndex) {
                                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 300)
                                        .clipped()
                                        .tag(index)
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
                            .frame(height: 300)
                        } else {
                            // Placeholder
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.3),
                                    Color.accentColor.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(height: 200)
                            .overlay(
                                Text(collection?.icon ?? "📝")
                                    .font(.system(size: 80))
                                    .opacity(0.5)
                            )
                        }
                
                        VStack(alignment: .leading, spacing: 20) {
                            // Header
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Collection badge
                                    if let collection = collection {
                                        HStack(spacing: 6) {
                                            Text(collection.icon)
                                            Text(collection.name)
                                                .fontWeight(.medium)
                                        }
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(Capsule())
                                    }

                                    // Title
                                    Text(entry.title)
                                        .font(.title)
                                        .fontWeight(.bold)
                                }

                                Spacer()

                                // Score
                                VStack(spacing: 4) {
                                    Text(entry.score.emoji)
                                        .font(.system(size: 48))
                                    Text(entry.score.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            // Date
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.secondary)
                                Text(entry.date, format: .dateTime.day().month(.wide).year())
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                    
                    // Additional Fields
                    if !metadataItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Details")
                                .font(.headline)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ForEach(metadataItems, id: \.key) { field in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(field.key)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(field.value)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    
                            // Description
                            if !entry.description.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Notes")
                                        .font(.headline)

                                    Text(entry.description)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            // Created date
                            HStack {
                                Spacer()
                                Text("Added \(entry.createdAt, format: .dateTime.day().month().year())")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 20)
                        }
                        .padding(20)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 12) {
                            Button {
                                showingEditSheet = true
                            } label: {
                                Image(systemName: "pencil.circle")
                            }

                            Menu {
                                Button(role: .destructive) {
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showingEditSheet) {
                    AddEntryView(editingEntryID: entryID)
                }
                .alert("Delete Entry", isPresented: $showingDeleteAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        Task {
                            await deleteEntry()
                        }
                    }
                } message: {
                    Text("Are you sure you want to delete \"\(entry.title)\"?")
                }
            } else {
                Text("Entry not found")
            }
        }
        .task {
            await loadEntry()
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

    private func loadEntry() async {
        isLoading = true
        errorMessage = nil

        do {
            // Load entry
            entry = try await EntryService.shared.getEntry(id: entryID)

            // Load collection if needed
            if let collectionID = entry?.collectionID {
                let collections = try await CollectionService.shared.getCollections()
                collection = collections.first { $0.id == collectionID }
            }

            // Load images using IDs from entry
            if let entry = entry {
                images = await loadImages(imageIDs: entry.images)
            }
        } catch {
            errorMessage = "Failed to load entry: \(error.localizedDescription)"
            showError = true
        }

        isLoading = false
    }

    private func loadImages(imageIDs: [ImageMeta]) async -> [UIImage] {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, imageMeta) in imageIDs.enumerated() {
                group.addTask {
                    guard let data = try? await EntryService.shared.getImage(imageID: imageMeta.id),
                          let uiImage = UIImage(data: data) else {
                        return (index, nil)
                    }
                    return (index, uiImage)
                }
            }
            var results: [(Int, UIImage?)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.compactMap { $0.1 }
        }
    }

    private func deleteEntry() async {
        isDeleting = true
        errorMessage = nil

        do {
            try await EntryService.shared.deleteEntry(id: entryID)
            dismiss()
        } catch {
            errorMessage = "Failed to delete entry: \(error.localizedDescription)"
            showError = true
            isDeleting = false
        }
    }
}

#Preview {
    NavigationStack {
        EntryDetailView(entryID: "preview-id")
    }
}
