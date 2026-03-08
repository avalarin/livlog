//
//  View+Utilities.swift
//  livlogios
//

import SwiftUI

// MARK: - View Extensions

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func glassOrMaterial<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
        }
        #else
        self.background(.thinMaterial, in: shape)
        #endif
    }

    @ViewBuilder
    func shimmerLoading(_ isLoading: Bool) -> some View {
        if isLoading {
            modifier(ShimmerModifier())
        } else {
            self
        }
    }
}

// MARK: - ShimmerModifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, .white.opacity(0.5), .clear],
                    startPoint: .init(x: phase, y: 0.5),
                    endPoint: .init(x: phase + 0.5, y: 0.5)
                )
                .frame(width: geo.size.width * 2)
                .offset(x: -geo.size.width)
            }
            .clipped()
        )
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.5
            }
        }
    }
}

// MARK: - EmptyStateView

struct EmptyStateView: View {
    @Binding var showingAddEntry: Bool
    var canWrite: Bool = true

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Text("📝")
                    .font(.system(size: 72))

                Text("Your Life Log is Empty")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Start tracking movies, books, games,\nand everything else you experience!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if canWrite {
                Button {
                    showingAddEntry = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                        Text("Add First Entry")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                    )
                    .foregroundStyle(.white)
                }
            }
        }
        .padding()
    }
}
