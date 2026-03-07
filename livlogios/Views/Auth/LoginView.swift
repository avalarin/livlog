//
//  LoginView.swift
//  livlogios
//
//  Created by Claude Code on 31.01.2026.
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var connectionMonitor = ConnectionMonitor.shared
    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showVerificationView = false
    @State private var resendCooldown: Int = 180

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Text("Welcome to Grove")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Track and rate your experiences")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)

                Spacer()

                // Email authentication section
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .disabled(isLoading)

                    Button {
                        handleEmailSignIn()
                    } label: {
                        Text("Sign in with email")
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(isEmailValid ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(!isEmailValid || isLoading)
                }
                .padding(.horizontal, 40)

                // Divider with "or"
                HStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                    Text("or")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal, 40)

                // Apple Sign In
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .padding(.horizontal, 40)
                    .cornerRadius(8)
                }

                ServerInfoView(
                    connectionMonitor: connectionMonitor,
                    showStatusDot: false,
                    onHostSwitch: { host in
                        ServerHost.selected = host
                        connectionMonitor.resetState()
                        Task {
                            await connectionMonitor.fetchServerVersion()
                        }
                    }
                )
                .padding(.bottom, 8)
            }
            .task {
                await connectionMonitor.fetchServerVersion()
            }
            .navigationDestination(isPresented: $showVerificationView) {
                EmailVerificationView(email: email, resendCooldown: resendCooldown)
                    .environmentObject(appState)
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("Try Again") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var isEmailValid: Bool {
        email.contains("@") && email.contains(".")
    }

    private func handleEmailSignIn() {
        guard isEmailValid else { return }

        isLoading = true

        Task {
            do {
                let response = try await appState.authService.sendVerificationCode(email: email)
                resendCooldown = response.resendCooldown
                showVerificationView = true
            } catch {
                if let authError = error as? AuthError {
                    errorMessage = authError.errorDescription
                } else {
                    errorMessage = "Failed to send verification code"
                }
            }
            isLoading = false
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        isLoading = true

        Task {
            do {
                switch result {
                case .success(let authorization):
                    _ = try await appState.authService.signInWithApple(authorization: authorization)
                    appState.isAuthenticated = true
                    appState.currentUser = appState.authService.currentUser

                case .failure(let error):
                    if let authError = error as? ASAuthorizationError {
                        switch authError.code {
                        case .canceled:
                            // User canceled, don't show error
                            break
                        case .failed:
                            errorMessage = "Failed to sign in with Apple"
                        case .invalidResponse:
                            errorMessage = "Invalid response from Apple"
                        case .notHandled:
                            errorMessage = "Sign in not handled"
                        case .unknown:
                            errorMessage = "Unknown error occurred"
                        @unknown default:
                            errorMessage = "An error occurred: " + authError.errorCode.description
                        }
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            } catch {
                if let authError = error as? AuthError {
                    errorMessage = authError.errorDescription
                } else {
                    errorMessage = "Failed to sign in: \(error.localizedDescription)"
                }
            }

            isLoading = false
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AppState())
}
