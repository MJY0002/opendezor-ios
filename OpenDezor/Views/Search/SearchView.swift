import SwiftUI

/// Full-page search across every installed addon, with a type filter that can be set
/// before typing as well as after the results arrive.
public struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel
    @FocusState private var isFieldFocused: Bool
    public var onSelectItem: (MediaItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 14)]

    public init(initialQuery: String = "", onSelectItem: @escaping (MediaItem) -> Void) {
        let model = SearchViewModel()
        model.query = initialQuery
        _viewModel = StateObject(wrappedValue: model)
        self.onSelectItem = onSelectItem
    }

    public var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 14) {
                content
            }
            .padding(.top, 4)
            Spacer().frame(height: 80)
        }
        .scrollDismissesKeyboard(.interactively)
        // Pinned, like the dashboard's bar: field and type chips stay reachable.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 10) {
                searchField
                scopeChips
            }
            .padding(.top, 4)
            .padding(.bottom, 10)
            .background(.bar)
        }
        .glassBackground()
        .navigationTitle(L("Suche"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // Searches 450 ms after the last keystroke; the next keystroke cancels it.
        .task(id: viewModel.query) { await viewModel.searchAfterPause() }
        .onAppear {
            if viewModel.query.isEmpty { isFieldFocused = true }
        }
    }

    // MARK: - Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppTheme.textSecondary)
                .appFont(size: 16)

            TextField(L("Filme, Serien, Live TV …"), text: $viewModel.query)
                .appFont(size: 15)
                .foregroundColor(AppTheme.textPrimary)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .submitLabel(.search)
                .focused($isFieldFocused)
                .onSubmit { Task { await viewModel.search(remember: true) } }

            if viewModel.isSearching {
                ProgressView().scaleEffect(0.8).tint(AppTheme.cyanAccent)
            } else if !viewModel.query.isEmpty {
                ClearFieldButton(size: 16) { viewModel.query = "" }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 18, fillColor: AppTheme.surface.opacity(0.85))
        .contentShape(Rectangle())
        .onTapGesture { isFieldFocused = true }
        .padding(.horizontal, 16)
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchScope.allCases) { scope in
                    chip(scope)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ scope: SearchScope) -> some View {
        let selected = viewModel.scope == scope
        let count = viewModel.searchedQuery == nil ? nil : viewModel.count(for: scope)
        return Button {
            withAnimation(AppMotion.standard) { viewModel.scope = scope }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scope.iconName).appFont(size: 12, weight: .semibold)
                Text(scope.title).appFont(size: 13, weight: .semibold)
                if let count {
                    Text("\(count)")
                        .appFont(size: 11, weight: .bold, design: .monospaced)
                        .opacity(0.7)
                }
            }
            .foregroundColor(selected ? .white : AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(selected ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(AppTheme.surfaceLight)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.searchedQuery == nil {
            if viewModel.isSearching {
                loadingGrid
            } else {
                recentSearches
            }
        } else if viewModel.visibleResults.isEmpty {
            if viewModel.isSearching { loadingGrid } else { emptyState }
        } else {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.visibleResults) { item in
                    MediaCardView(item: item, shape: SearchScope.classify(item) == .live ? .square : .portrait) {
                        onSelectItem(item)
                    }
                }
            }
            .padding(.horizontal, 16)
            // Keep the old hits visible and dimmed while a refined search is running.
            .opacity(viewModel.isSearching ? 0.5 : 1)
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<9, id: \.self) { _ in CardSkeletonView(width: 145, height: 210) }
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .appFont(size: 40)
                .foregroundColor(AppTheme.textTertiary)
            Text(L("Nichts gefunden"))
                .appFont(size: 16, weight: .bold)
                .foregroundColor(AppTheme.textPrimary)
            if viewModel.scope != .all, viewModel.count(for: .all) > 0 {
                Button(L("In allen Kategorien suchen")) { viewModel.scope = .all }
                    .appFont(size: 13, weight: .semibold)
                    .foregroundColor(AppTheme.primaryAccent)
            }
        }
        .padding(.vertical, 60)
    }

    @ViewBuilder
    private var recentSearches: some View {
        let recents = viewModel.recentSearches
        if recents.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .appFont(size: 40)
                    .foregroundColor(AppTheme.textTertiary)
                Text(L("Alle installierten Addons durchsuchen"))
                    .appFont(size: 14)
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 60)
            .padding(.horizontal, 32)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Letzte Suchen"))
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                ForEach(recents, id: \.self) { term in
                    Button {
                        viewModel.query = term
                        Task { await viewModel.search(remember: true) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(AppTheme.textTertiary)
                            Text(term)
                                .appFont(size: 15)
                                .foregroundColor(AppTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
