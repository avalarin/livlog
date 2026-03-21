# Livlog Justfile

# Default recipe
default:
    @just --list

# --- iOS ---

simulator := "iPhone 17 Pro"
device := ""
scheme := "livlogios"
project := "livlogios.xcodeproj"
bundle_id := "net.avalarin.groveapp"
team_id := "ZY6GYZY62T"

# Build and run iOS app (simulator by default, or device with: just device="iPhone" ios-run)
ios-run:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "{{device}}" ]; then
        echo "Building for device: {{device}}..."
        xcodebuild build \
            -project {{project}} \
            -scheme {{scheme}} \
            -destination 'platform=iOS,name={{device}}' \
            -configuration Debug \
            -allowProvisioningUpdates \
            DEVELOPMENT_TEAM={{team_id}} \
            | tail -n 5
        echo "Installing and launching on {{device}}..."
        xcrun devicectl device install app \
            --device "{{device}}" \
            "$(xcodebuild build \
                -project {{project}} \
                -scheme {{scheme}} \
                -destination 'platform=iOS,name={{device}}' \
                -configuration Debug \
                -allowProvisioningUpdates \
                DEVELOPMENT_TEAM={{team_id}} \
                -showBuildSettings 2>/dev/null \
              | grep -m1 'BUILT_PRODUCTS_DIR' \
              | sed 's/.*= //')/{{scheme}}.app"
        xcrun devicectl device process launch --device "{{device}}" {{bundle_id}}
    else
        echo "Building for simulator: {{simulator}}..."
        xcodebuild build \
            -project {{project}} \
            -scheme {{scheme}} \
            -destination 'platform=iOS Simulator,name={{simulator}}' \
            -configuration Debug \
            DEVELOPMENT_TEAM={{team_id}} \
            | tail -n 5
        xcrun simctl boot "{{simulator}}" 2>/dev/null || true
        open -a Simulator
        APP_PATH=$(xcodebuild build \
            -project {{project}} \
            -scheme {{scheme}} \
            -destination 'platform=iOS Simulator,name={{simulator}}' \
            -configuration Debug \
            DEVELOPMENT_TEAM={{team_id}} \
            -showBuildSettings 2>/dev/null \
          | grep -m1 'BUILT_PRODUCTS_DIR' \
          | sed 's/.*= //')
        xcrun simctl install booted "$APP_PATH/{{scheme}}.app"
        xcrun simctl launch booted {{bundle_id}}
    fi

# Build iOS app for simulator
ios-build:
    xcodebuild build \
        -project {{project}} \
        -scheme {{scheme}} \
        -destination 'platform=iOS Simulator,name={{simulator}}' \
        -configuration Debug \
        DEVELOPMENT_TEAM={{team_id}} \
        | tail -n 5

# Run iOS tests
ios-test:
    xcodebuild test \
        -project {{project}} \
        -scheme {{scheme}} \
        -destination 'platform=iOS Simulator,name={{simulator}}' \
        DEVELOPMENT_TEAM={{team_id}}

# Clean iOS build artifacts
ios-clean:
    xcodebuild clean -project {{project}} -scheme {{scheme}}

# List connected iOS devices
ios-devices:
    xcrun devicectl list devices

# List available simulators
ios-simulators:
    xcrun simctl list devices available

# --- Backend ---

# Build backend
backend-build:
    just --justfile ./backend/Justfile --working-directory ./backend build

# Run backend locally
backend-run:
    just --justfile ./backend/Justfile --working-directory ./backend run

# Run backend tests
backend-test:
    just --justfile ./backend/Justfile --working-directory ./backend test

# Run backend linter
backend-lint:
    just --justfile ./backend/Justfile --working-directory ./backend lint
