//
//  CustomizeStatisticsView.swift
//  livlogios
//

import SwiftUI

struct CustomizeStatisticsView: View {
    let collectionID: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var availableStats: [AvailableStatistic] = []
    @State private var enabledIDs: [String] = []  // ordered list of enabled stat IDs
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(enabledIDs, id: \.self) { statID in
                        if let stat = availableStats.first(where: { $0.id == statID }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stat.title)
                                        .font(.body)
                                    Text(stat.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    withAnimation {
                                        enabledIDs.removeAll { $0 == statID }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .onMove { from, to in
                        enabledIDs.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Shown")
                }

                Section {
                    let disabledStats = availableStats.filter { !enabledIDs.contains($0.id) }
                    ForEach(disabledStats) { stat in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stat.title)
                                    .font(.body)
                                Text(stat.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                withAnimation {
                                    enabledIDs.append(stat.id)
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Available")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
            .task {
                await loadData()
            }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let stats = try await CollectionService.shared.getAvailableStatistics(collectionID: collectionID)
            availableStats = stats
            enabledIDs = stats.filter { $0.isEnabled }.sorted { $0.position < $1.position }.map { $0.id }
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            errorMessage = "Failed to load statistics: \(error.localizedDescription)"
            showError = true
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await CollectionService.shared.updateStatisticsConfig(
                collectionID: collectionID,
                statisticIDs: enabledIDs
            )
            onDismiss()
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            showError = true
        }
    }
}

#if DEBUG
#Preview {
    CustomizeStatisticsView(collectionID: "my-list") { }
}
#endif
