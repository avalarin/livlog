# Connection Monitoring

## Overview

The connection monitoring system provides real-time feedback to users about backend service availability with persistent toast notifications and countdown timers.

## Components

### ConnectionMonitor

`ConnectionMonitor.swift` is a singleton service that periodically checks backend health and manages toast notifications.

**Key Features:**
- Automatic health checks every 10 seconds
- Countdown timer showing seconds until next retry attempt
- Persistent error toast (stays visible until connection restored)
- Auto-dismissing success toast (3 seconds)
- Published properties for reactive UI updates

**Properties:**
- `status: ConnectionStatus` - Current connection state (unknown/connected/disconnected)
- `showToast: Bool` - Whether toast should be displayed
- `toastMessage: String` - Message to display in toast
- `isToastSuccess: Bool` - Whether toast indicates success or error
- `secondsUntilNextCheck: Int` - Countdown value for next retry

**Methods:**
- `startMonitoring()` - Begin periodic health checks
- `stopMonitoring()` - Stop monitoring and cleanup tasks
- `dismissToast()` - Manually dismiss the toast

### ConnectionToastView

`ConnectionToastView.swift` provides the visual representation of connection status.

**Visual Design:**
- **Error state**: Soft red background (`Color.red.opacity(0.15)`) with red border
- **Success state**: Soft green background (`Color.green.opacity(0.15)`) with green border
- **Size**: Larger than standard toasts (20px horizontal padding, 16px vertical padding)
- **Countdown**: Displays "Retry in Xs" text below error message
- **Dismiss button**: Only shown for success toasts (errors persist until resolved)

## Usage

The monitoring system is automatically initialized in `livlogiosApp.swift`:

```swift
@StateObject private var connectionMonitor = ConnectionMonitor.shared

var body: some Scene {
    WindowGroup {
        ContentView()
            .connectionToast(monitor: connectionMonitor)
            .onAppear {
                connectionMonitor.startMonitoring()
            }
    }
}
```

## Behavior

1. **Initial Check**: Performs health check immediately on app launch
2. **Periodic Checks**: Repeats every 10 seconds while app is running
3. **Error State**: When backend is unavailable:
   - Shows persistent red toast with error message
   - Displays countdown timer (10→0 seconds)
   - Toast remains visible until connection restored
4. **Recovery**: When connection is restored:
   - Shows green success toast
   - Auto-dismisses after 3 seconds
   - User can manually dismiss with X button

## Configuration

Health check endpoint is configured in `AppConfig.swift`:
- Default interval: 10 seconds
- Request timeout: 5 seconds
- Success criteria: HTTP 200 with `status: "ok"` and `database.status: "connected"`
