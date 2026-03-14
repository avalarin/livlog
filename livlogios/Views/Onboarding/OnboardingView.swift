//
//  OnboardingView.swift
//  livlogios
//
//  Created by Claude Code on 08.03.2026.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep = 0
    @State private var displayName = ""
    @State private var selectedTemplateSlug: String?
    @State private var templates: [CollectionTemplate] = []
    @State private var isLoading = false
    @State private var isCompleting = false
    @State private var errorMessage: String?

    private let totalSteps = 2

    private var isNameValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator

                TabView(selection: $currentStep) {
                    OnboardingNameStepView(displayName: $displayName)
                        .tag(0)

                    OnboardingCollectionStepView(
                        templates: templates,
                        selectedSlug: $selectedTemplateSlug
                    )
                    .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
                .onChange(of: currentStep) { _, newValue in
                    if newValue > 0 && !isNameValid {
                        currentStep = 0
                    }
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation { currentStep -= 1 }
                        }
                    }

                    Spacer()

                    if currentStep < totalSteps - 1 {
                        Button("Next") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            withAnimation { currentStep += 1 }
                        }
                        .disabled(!isNameValid)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            Task { await completeOnboarding() }
                        } label: {
                            if isCompleting {
                                ProgressView()
                            } else {
                                Text("Save")
                            }
                        }
                        .disabled(isCompleting)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .task {
            await loadTemplates()
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut, value: currentStep)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func loadTemplates() async {
        isLoading = true
        defer { isLoading = false }
        do {
            templates = try await OnboardingService.shared.getTemplates()
        } catch {
            // Templates can fail gracefully — user can still complete without selecting one
        }
    }

    private func completeOnboarding() async {
        isCompleting = true
        defer { isCompleting = false }
        errorMessage = nil
        do {
            let slug = selectedTemplateSlug == "create-later" ? nil : selectedTemplateSlug
            try await OnboardingService.shared.completeOnboarding(
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                templateSlug: slug
            )
            await appState.completeOnboarding()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
