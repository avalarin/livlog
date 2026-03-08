//
//  EntryListRow.swift
//  livlogios
//

import SwiftUI

struct EntryListRow: View {
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
        if item.description.isEmpty {
            return "(no notes)"
        }
        let firstLine = item.description.components(separatedBy: .newlines).first ?? ""
        return firstLine.isEmpty ? "(no notes)" : firstLine
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text(entryType?.icon ?? "📝")
                    .font(.system(size: 40))
                    .opacity(isImageLoading ? 0 : 1)
                    .frame(width: 60, height: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                    .shimmerLoading(isImageLoading)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if !metadataLine.isEmpty {
                        Text(metadataLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if isSelectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                } else {
                    Text(item.score.emoji)
                        .font(.title3)
                }

                Text(item.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color.gray.opacity(0.2) : Color.clear))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
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
