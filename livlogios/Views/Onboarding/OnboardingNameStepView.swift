//
//  OnboardingNameStepView.swift
//  livlogios
//
//  Created by Claude Code on 08.03.2026.
//

import SwiftUI

struct OnboardingNameStepView: View {
    @Binding var displayName: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Welcome to livlog!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("What should we call you?")
                .font(.title3)
                .foregroundColor(.secondary)

            TextField("Your name", text: $displayName)
                .textContentType(.name)
                .autocorrectionDisabled()
                .padding()
                .background(.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 20)

            Text("This name will be visible to other users")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
            Spacer()
        }
        .padding()
    }
}

#Preview {
    OnboardingNameStepView(displayName: .constant(""))
}
