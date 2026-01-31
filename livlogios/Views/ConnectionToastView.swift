//
//  ConnectionToastView.swift
//  livlogios
//
//  Created by avprokopev on 31.01.2026.
//

import SwiftUI

struct ConnectionToastView: View {
    let message: String
    let isSuccess: Bool
    let secondsUntilNextCheck: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(isSuccess ? Color.green : Color.red)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                if !isSuccess {
                    if secondsUntilNextCheck > 0 {
                        Text("Retry in \(secondsUntilNextCheck)s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Trying to reconnect...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if isSuccess {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSuccess ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
    }
}

struct ConnectionToastModifier: ViewModifier {
    @ObservedObject var monitor: ConnectionMonitor

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if monitor.showToast {
                    ConnectionToastView(
                        message: monitor.toastMessage,
                        isSuccess: monitor.isToastSuccess,
                        secondsUntilNextCheck: monitor.secondsUntilNextCheck,
                        onDismiss: { monitor.dismissToast() }
                    )
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: monitor.showToast)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: monitor.showToast)
    }
}

extension View {
    func connectionToast(monitor: ConnectionMonitor) -> some View {
        modifier(ConnectionToastModifier(monitor: monitor))
    }
}

#Preview("Success Toast") {
    VStack {
        Text("Main Content")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .bottom) {
        ConnectionToastView(
            message: "Connection restored",
            isSuccess: true,
            secondsUntilNextCheck: 0,
            onDismiss: {}
        )
        .padding(.bottom, 16)
    }
}

#Preview("Error Toast") {
    VStack {
        Text("Main Content")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .bottom) {
        ConnectionToastView(
            message: "Service unavailable",
            isSuccess: false,
            secondsUntilNextCheck: 8,
            onDismiss: {}
        )
        .padding(.bottom, 16)
    }
}
