//
//  ServerInfoView.swift
//  livlogios
//

import SwiftUI

struct ServerInfoView: View {
    @ObservedObject var connectionMonitor: ConnectionMonitor
    var showStatusDot: Bool = true
    var onHostSwitch: ((ServerHost) -> Void)?

    @State private var showHostPicker = false

    var body: some View {
        VStack(spacing: 4) {
            statusRow
            if AppConfig.isDevBuild {
                hostRow
            }
        }
    }

    // MARK: - Subviews

    private var statusRow: some View {
        HStack(spacing: 6) {
            if showStatusDot {
                Circle()
                    .fill(connectionMonitor.status.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }
            Text(connectionMonitor.serverVersion ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var hostRow: some View {
        Button {
            showHostPicker = true
        } label: {
            Text(ServerHost.selected.displayHost)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            "Select Server",
            isPresented: $showHostPicker,
            titleVisibility: .visible
        ) {
            ForEach(ServerHost.allCases, id: \.rawValue) { host in
                Button(host.label) {
                    onHostSwitch?(host)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

#Preview {
    ServerInfoView(
        connectionMonitor: ConnectionMonitor.shared,
        showStatusDot: true,
        onHostSwitch: nil
    )
    .padding()
}
