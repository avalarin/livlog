//
//  OnboardingCollectionStepView.swift
//  livlogios
//
//  Created by Claude Code on 08.03.2026.
//

import SwiftUI

struct OnboardingCollectionStepView: View {
    let templates: [CollectionTemplate]
    @Binding var selectedSlug: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Create your first collection")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)

            Text("Choose a collection to get started with sample entries")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(templates) { template in
                        TemplateCardView(
                            template: template,
                            isSelected: selectedSlug == template.slug
                        ) {
                            selectedSlug = template.slug
                        }
                    }

                    createLaterCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
        }
    }

    private var createLaterCard: some View {
        Button {
            selectedSlug = "create-later"
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Create later")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Skip for now, create a collection anytime")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: selectedSlug == "create-later" ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedSlug == "create-later" ? .accentColor : .gray.opacity(0.3))
                    .font(.title3)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedSlug == "create-later" ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TemplateCardView: View {
    let template: CollectionTemplate
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                CollectionIconView(iconRaw: template.icon, colorRaw: template.color, size: 40)

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

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .gray.opacity(0.3))
                    .font(.title3)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingCollectionStepView(
        templates: [
            CollectionTemplate(slug: "movies", name: "Movies", description: "Track movies you've watched", icon: "system:movie", color: "dodger-blue"),
            CollectionTemplate(slug: "books", name: "Books", description: "Track books you've read", icon: "system:bookmark", color: "verdigris")
        ],
        selectedSlug: .constant("movies")
    )
}
