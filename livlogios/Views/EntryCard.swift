//
//  EntryCard.swift
//  livlogios
//

import SwiftUI

struct EntryCard: View {
    let item: EntryModel
    let entryType: EntryTypeModel?
    var onDelete: (() async -> Void)?
    var isSelectMode: Bool = false
    var isSelected: Bool = false
    var canWrite: Bool = true

    @State private var showingDeleteAlert = false
    @State private var isDeleting = false
    @State private var coverImage: UIImage?
    @State private var isImageLoading = false

    private var metadataLine: String {
        let line = item.additionalFields.values.joined(separator: "・")
        return line.isEmpty ? "-" : line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.3),
                        Color.accentColor.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .overlay(
                    Text(entryType?.icon ?? "📝")
                        .font(.system(size: 48))
                        .opacity(coverImage == nil && isImageLoading ? 0 : 0.5)
                )
                .shimmerLoading(coverImage == nil && isImageLoading)

                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .layoutPriority(-1)
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(item.score.emoji)
                    .font(.title3)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 4) {
                    Text(entryType?.icon ?? "📝")
                        .font(.caption)
                    Text(item.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if !metadataLine.isEmpty {
                    Text(metadataLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !item.description.isEmpty {
                    Text(item.description + "\n")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).fill(isSelected ? Color.gray.opacity(0.2) : Color.clear))
        .overlay(alignment: .bottomTrailing) {
            if isSelectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(8)
            }
        }
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        .opacity(isDeleting ? 0.5 : 1.0)
        .if(!isSelectMode && onDelete != nil) { view in
            view.contextMenu {
                if canWrite {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .alert("Delete Entry", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let onDelete {
                    Task {
                        isDeleting = true
                        await onDelete()
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(item.title)\"?")
        }
        .task(id: item.id) {
            await loadCoverImage()
        }
    }

    private func loadCoverImage() async {
        let cover = item.images.first { $0.isCover } ?? item.images.first
        guard let cover else { return }
        isImageLoading = true
        defer { isImageLoading = false }
        guard let image = try? await ImageLoaderService.shared.load(id: cover.id, hash: cover.hash) else { return }
        coverImage = image
    }
}
