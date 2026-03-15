//
//  SettingsView.swift
//  livlogios
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var connectionMonitor = ConnectionMonitor.shared

    @State private var mcpStatus: MCPStatusResponse?
    @State private var isLoadingMCP = false
    @State private var isTogglingMCP = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var toastMessage: String?
    @State private var showDeleteAccountAlert = false
    @State private var showHostSwitchAlert = false
    @State private var pendingHost: ServerHost?
    @State private var showingEditName = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Account Section
                Section("Account") {
                    if let user = appState.currentUser {
                        if let email = user.email {
                            LabeledContent("Email", value: email)
                        }
                        if let name = user.displayName {
                            HStack {
                                Text("Name")
                                Spacer()
                                Text(name)
                                    .foregroundStyle(.secondary)
                                Button {
                                    showingEditName = true
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                // MARK: - MCP Integration Section
                Section {
                    if isLoadingMCP {
                        HStack {
                            ProgressView()
                            Text("Loading...")
                                .foregroundStyle(.secondary)
                        }
                    } else if let status = mcpStatus {
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(status.enabled ? "Active" : "Disabled")
                                .foregroundStyle(status.enabled ? .green : .secondary)
                        }

                        if status.enabled, let url = status.url {
                            HStack(spacing: 8) {
                                Text(url)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Button {
                                    copyURL(url)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            Task {
                                if mcpStatus?.enabled == true {
                                    await disableMCP()
                                } else {
                                    await enableMCP()
                                }
                            }
                        } label: {
                            if isTogglingMCP {
                                HStack {
                                    ProgressView()
                                    Text(mcpStatus?.enabled == true ? "Disabling..." : "Enabling...")
                                }
                            } else {
                                Text(mcpStatus?.enabled == true ? "Disable Integration" : "Enable Integration")
                                    .foregroundStyle(mcpStatus?.enabled == true ? .red : .accentColor)
                            }
                        }
                        .disabled(isTogglingMCP)
                    }
                } header: {
                    Text("External Integrations (MCP)")
                } footer: {
                    if mcpStatus?.enabled == true {
                        Text("Share this URL with your AI agents to let them access your collections.")
                    } else {
                        Text("Enable to get a URL you can connect to external AI agents via the Model Context Protocol.")
                    }
                }

                // MARK: - Danger Zone
                Section {
                    Button("Log Out") {
                        Task {
                            await appState.logout()
                            dismiss()
                        }
                    }
                    .foregroundStyle(.red)

                    Button("Delete Account", role: .destructive) {
                        showDeleteAccountAlert = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadMCPStatus()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let msg = errorMessage { Text(msg) }
            }
            .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await appState.deleteAccount()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            } message: {
                Text("This will permanently delete your account and all data. This cannot be undone.")
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if let message = toastMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.75), in: Capsule())
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    ServerInfoView(
                        connectionMonitor: connectionMonitor,
                        showStatusDot: true,
                        onHostSwitch: { host in
                            pendingHost = host
                            showHostSwitchAlert = true
                        }
                    )
                }
                .padding(.bottom, 24)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toastMessage)
            .sheet(isPresented: $showingEditName) {
                EditDisplayNameView(
                    currentName: appState.currentUser?.displayName ?? ""
                )
            }
            .alert("Switch Server", isPresented: $showHostSwitchAlert) {
                Button("Cancel", role: .cancel) { pendingHost = nil }
                Button("Continue", role: .destructive) {
                    guard let host = pendingHost else { return }
                    ServerHost.selected = host
                    connectionMonitor.resetState()
                    Task {
                        await appState.logout()
                        dismiss()
                    }
                }
            } message: {
                Text("Changing server will log you out. Continue?")
            }
        }
    }

    // MARK: - Actions

    private func loadMCPStatus() async {
        isLoadingMCP = true
        do {
            mcpStatus = try await MCPService.shared.getStatus()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoadingMCP = false
    }

    private func enableMCP() async {
        isTogglingMCP = true
        do {
            mcpStatus = try await MCPService.shared.enable()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isTogglingMCP = false
    }

    private func disableMCP() async {
        isTogglingMCP = true
        do {
            try await MCPService.shared.disable()
            mcpStatus = MCPStatusResponse(enabled: false, url: nil)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isTogglingMCP = false
    }

    private func copyURL(_ url: String) {
        UIPasteboard.general.string = url
        toastMessage = "URL copied to clipboard"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toastMessage = nil
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
