//
//  EntryDetailView.swift
//  livlogios
//
//  Created by avprokopev on 31.12.2025.
//

import SwiftUI
import SwiftData

struct EntryDetailView: View {
    let item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    @State private var selectedImageIndex: Int = 0
    
    private var images: [UIImage] {
        item.images.compactMap { UIImage(data: $0) }
    }
    
    private var metadataItems: [(key: String, value: String)] {
        let fieldOrder = ["Year", "Genre", "Author", "Platform"]
        return item.additionalFields.sorted { a, b in
            let indexA = fieldOrder.firstIndex(of: a.key) ?? Int.max
            let indexB = fieldOrder.firstIndex(of: b.key) ?? Int.max
            return indexA < indexB
        }
    }
    
    var body: some View {
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
                        Text(item.collection?.icon ?? "📝")
                            .font(.system(size: 80))
                            .opacity(0.5)
                    )
                }
                
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            // Collection badge
                            if let collection = item.collection {
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
                            Text(item.title)
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        
                        Spacer()
                        
                        // Score
                        VStack(spacing: 4) {
                            Text(item.score.emoji)
                                .font(.system(size: 48))
                            Text(item.score.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Date
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                        Text(item.date, format: .dateTime.day().month(.wide).year())
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
                    if !item.entryDescription.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                            
                            Text(item.entryDescription)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Created date
                    HStack {
                        Spacer()
                        Text("Added \(item.createdAt, format: .dateTime.day().month().year())")
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
            AddEntryView(editingItem: item)
        }
        .alert("Delete Entry", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(item)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete \"\(item.title)\"?")
        }
    }
}

#Preview {
    NavigationStack {
        EntryDetailView(
            item: Item(
                collection: nil,
                title: "Inception",
                entryDescription: "A mind-bending masterpiece by Christopher Nolan. The film explores the concept of dream invasion and features stunning visual effects.",
                score: .great,
                date: Date(),
                additionalFields: ["Year": "2010", "Genre": "Sci-Fi, Thriller"]
            )
        )
    }
    .modelContainer(for: [Collection.self, Item.self], inMemory: true)
}
