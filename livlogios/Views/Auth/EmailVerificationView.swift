//
//  EmailVerificationView.swift
//  livlogios
//
//  Created by Claude Code on 01.02.2026.
//

import SwiftUI

struct EmailVerificationView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let email: String

    @State private var code: [String] = Array(repeating: "", count: 6)
    @FocusState private var focusedField: Int?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var resendTimer: Int = 60
    @State private var timerActive = true

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Text("Enter verification code")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("We sent a code to \(email)")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            .padding(.top, 60)

            // 6-digit code input
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    TextField("", text: $code[index])
                        .frame(width: 45, height: 55)
                        .multilineTextAlignment(.center)
                        .keyboardType(.numberPad)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .focused($focusedField, equals: index)
                        .onChange(of: code[index]) { oldValue, newValue in
                            handleCodeInput(at: index, oldValue: oldValue, newValue: newValue)
                        }
                        .disabled(isLoading)
                }
            }
            .padding(.horizontal, 20)

            // Sign in button
            Button {
                handleVerify()
            } label: {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Sign In")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(isCodeComplete ? Color.blue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(!isCodeComplete || isLoading)
            .padding(.horizontal, 40)

            // Resend button
            Button {
                handleResend()
            } label: {
                if timerActive {
                    Text("Resend code in \(resendTimer)s")
                        .foregroundColor(.secondary)
                } else {
                    Text("Resend code")
                        .foregroundColor(.blue)
                }
            }
            .disabled(timerActive || isLoading)

            Spacer()
        }
        .navigationBarBackButtonHidden(false)
        .onAppear {
            focusedField = 0
            startResendTimer()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isCodeComplete: Bool {
        code.allSatisfy { $0.count == 1 }
    }

    private func handleCodeInput(at index: Int, oldValue: String, newValue: String) {
        // Only keep last character
        if newValue.count > 1 {
            code[index] = String(newValue.last!)
        }

        // Only allow digits
        if !newValue.isEmpty && !newValue.allSatisfy(\.isNumber) {
            code[index] = oldValue
            return
        }

        // Auto-advance to next field
        if newValue.count == 1 && index < 5 {
            focusedField = index + 1
        }

        // Auto-submit when all 6 digits entered
        if isCodeComplete {
            handleVerify()
        }
    }

    private func handleVerify() {
        guard isCodeComplete else { return }

        isLoading = true
        let fullCode = code.joined()

        Task {
            do {
                _ = try await appState.authService.signInWithEmail(
                    email: email,
                    code: fullCode
                )
                appState.isAuthenticated = true
                appState.currentUser = appState.authService.currentUser
            } catch {
                if let authError = error as? AuthError {
                    errorMessage = authError.errorDescription
                } else {
                    errorMessage = "Failed to verify code"
                }

                // Clear code on error
                code = Array(repeating: "", count: 6)
                focusedField = 0
            }
            isLoading = false
        }
    }

    private func handleResend() {
        guard !timerActive else { return }

        isLoading = true

        Task {
            do {
                _ = try await appState.authService.resendVerificationCode(email: email)
                resetResendTimer()
            } catch {
                if let authError = error as? AuthError {
                    errorMessage = authError.errorDescription
                } else {
                    errorMessage = "Failed to resend code"
                }
            }
            isLoading = false
        }
    }

    private func startResendTimer() {
        resendTimer = 60
        timerActive = true

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if resendTimer > 0 {
                resendTimer -= 1
            } else {
                timerActive = false
                timer.invalidate()
            }
        }
    }

    private func resetResendTimer() {
        startResendTimer()
    }
}

#Preview {
    NavigationStack {
        EmailVerificationView(email: "test@example.com")
            .environmentObject(AppState())
    }
}
