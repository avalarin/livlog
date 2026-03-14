//
//  TemplatePickerView.swift
//  livlogios
//

import SwiftUI

struct TemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var templates: [CollectionTemplate] = []
    @State private var isLoading = false
    @State private var selectedTemplate: CollectionTemplate?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && templates.isEmpty {
                    ProgressView()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(templates) { template in
                                Button {
                                    selectedTemplate = template
                                } label: {
                                    HStack(spacing: 12) {
                                        CollectionIconView(
                                            iconRaw: template.icon,
                                            colorRaw: template.color,
                                            size: 40
                                        )

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(template.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(template.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemBackground))
                                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedTemplate) { template in
                AddEditCollectionView(mode: .addFromTemplate(template))
                    .onDisappear {
                        if selectedTemplate == nil {
                            dismiss()
                        }
                    }
            }
        }
        .task {
            await loadTemplates()
        }
    }

    private func loadTemplates() async {
        isLoading = true
        defer { isLoading = false }
        do {
            templates = try await OnboardingService.shared.getTemplates()
        } catch {
            // Fail gracefully
        }
    }
}

#Preview {
    TemplatePickerView()
}
