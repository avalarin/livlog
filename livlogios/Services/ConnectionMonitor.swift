//
//  ConnectionMonitor.swift
//  livlogios
//
//  Created by avprokopev on 31.01.2026.
//

import Combine
import Foundation

enum ConnectionStatus: Equatable {
    case unknown
    case connected
    case disconnected

    var isConnected: Bool {
        self == .connected
    }
}

@MainActor
final class ConnectionMonitor: ObservableObject {
    static let shared = ConnectionMonitor()

    @Published private(set) var status: ConnectionStatus = .unknown
    @Published private(set) var serverVersion: String?
    @Published private(set) var showToast: Bool = false
    @Published private(set) var toastMessage: String = ""
    @Published private(set) var isToastSuccess: Bool = false
    @Published private(set) var secondsUntilNextCheck: Int = 0

    private var checkTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private let checkInterval: TimeInterval = 10

    private init() {}

    func startMonitoring() {
        stopMonitoring()

        checkTask = Task { [weak self] in
            guard let self = self else { return }

            // Initial check
            await self.performHealthCheck()

            // Periodic checks
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(self.checkInterval * 1_000_000_000))
                } catch {
                    break
                }
                await self.performHealthCheck()
            }
        }
    }

    func stopMonitoring() {
        checkTask?.cancel()
        checkTask = nil
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func performHealthCheck() async {
        let healthResponse = await BackendService.shared.checkHealth()
        let isHealthy = healthResponse?.isHealthy ?? false
        let newStatus: ConnectionStatus = isHealthy ? .connected : .disconnected

        if let version = healthResponse?.version {
            serverVersion = version
        }

        // Only show toast on status change (not on initial unknown state)
        if newStatus == .disconnected || (newStatus == .connected && status == .disconnected) {
            showStatusToast(isConnected: isHealthy)
        }

        status = newStatus

        // Start countdown if disconnected
        if newStatus == .disconnected {
            startCountdown()
        }
    }

    func fetchServerVersion() async {
        guard serverVersion == nil else { return }
        let response = await BackendService.shared.checkHealth()
        if let version = response?.version {
            serverVersion = version
        }
    }

    func resetState() {
        stopMonitoring()
        status = .unknown
        serverVersion = nil
        showToast = false
        toastMessage = ""
        isToastSuccess = false
        secondsUntilNextCheck = 0
    }

    private func showStatusToast(isConnected: Bool) {
        toastDismissTask?.cancel()

        isToastSuccess = isConnected
        toastMessage = isConnected ? "Connection restored" : "Service unavailable"
        showToast = true

        // Only auto-dismiss success toast, error toast stays until connection is restored
        if isConnected {
            toastDismissTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    return
                }
                self?.showToast = false
            }
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        secondsUntilNextCheck = Int(checkInterval)

        countdownTask = Task { [weak self] in
            guard let self = self else { return }

            while self.secondsUntilNextCheck > 0 {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                self.secondsUntilNextCheck -= 1
            }
        }
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        showToast = false
    }
}
