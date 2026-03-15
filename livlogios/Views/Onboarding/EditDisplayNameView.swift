//
//  EditDisplayNameView.swift
//  livlogios
//

import SwiftUI

struct EditDisplayNameView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var displayName: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    let isOnboarding: Bool

    init(currentName: String = "", isOnboarding: Bool = false) {
        _displayName = State(initialValue: currentName)
        self.isOnboarding = isOnboarding
    }

    private var isNameValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text(isOnboarding ? "Welcome to livlog!" : "Edit Name")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                if isOnboarding {
                    Text("What should we call you?")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                TextField("Your name", text: $displayName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20)

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                if isOnboarding {
                    Text("This name will be visible to other users")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isOnboarding {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                    .tint(.accentColor)
                    .disabled(!isNameValid || isSaving)
                }
            }
            .interactiveDismissDisabled(isOnboarding)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        do {
            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            try await OnboardingService.shared.updateDisplayName(trimmedName)

            if isOnboarding {
                try await OnboardingService.shared.completeOnboarding()
                await appState.completeOnboarding()
            } else {
                await appState.completeOnboarding() // re-fetches currentUser
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    EditDisplayNameView(isOnboarding: true)
        .environmentObject(AppState())
}
