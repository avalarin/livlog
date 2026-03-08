//
//  SearchView.swift
//  livlogios
//

import SwiftUI

struct SearchView: View {
    let types: [EntryTypeModel]

    @Environment(\.dismiss) private var dismiss

    @FocusState private var isSearchFocused: Bool

    @State private var path = NavigationPath()
    @State private var query = ""
    /// nil = not yet searched; [] = searched, no results; non-empty = results
    @State private var results: [EntryModel]?
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                contentView
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { entryID in
                EntryDetailView(entryID: entryID)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if path.isEmpty {
                searchBar
            }
        }
        .onAppear {
            isSearchFocused = true
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            emptyQueryView
        } else if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let results {
            if results.isEmpty {
                noResultsView
            } else {
                resultsView(results)
            }
        } else {
            // Query typed, debounce pending — show prompt while waiting
            emptyQueryView
        }
    }

    private var emptyQueryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Search your entries")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Type to find movies, books, games,\nand everything else you've logged.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No results found")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Nothing matched \"\(query)\".\nTry a different search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func resultsView(_ items: [EntryModel]) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                HStack {
                    Text("\(items.count) found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ForEach(items) { item in
                    let entryType = types.first { $0.id == item.typeID }
                    NavigationLink(value: item.id) {
                        EntryListRow(item: item, entryType: entryType)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                TextField("Search entries...", text: $query)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onChange(of: query) { _, newValue in
                        searchTask?.cancel()
                        results = nil
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { return }
                        searchTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            await performSearch(trimmed)
                        }
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                        results = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassOrMaterial(in: RoundedRectangle(cornerRadius: 16))

            Button {
                searchTask?.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .glassOrMaterial(in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func performSearch(_ searchQuery: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await EntryService.shared.searchEntries(query: searchQuery)
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

#Preview {
    SearchView(types: [])
}
