import SwiftUI

public struct CatalogGridView: View {
    @StateObject private var viewModel: CatalogViewModel
    @State private var showFilterSheet: Bool = false
    public var onSelectItem: (MediaItem) -> Void
    
    public init(
        addonEndpoint: String,
        catalogId: String,
        catalogName: String,
        features: CatalogFeatures? = nil,
        onSelectItem: @escaping (MediaItem) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: CatalogViewModel(
                addonEndpoint: addonEndpoint,
                catalogId: catalogId,
                catalogName: catalogName,
                features: features
            )
        )
        self.onSelectItem = onSelectItem
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 145, maximum: 190), spacing: 14)
    ]
    
    public var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    // Search & Filter Header Bar
                    headerBar
                    
                    // Main Grid
                    if viewModel.isLoading {
                        loadingGrid
                    } else if viewModel.items.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.items) { item in
                                MediaCardView(item: item, shape: .portrait) {
                                    onSelectItem(item)
                                }
                                .onAppear {
                                    viewModel.loadMoreIfNeeded(currentItem: item)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Loading More Spinner
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(AppTheme.primaryAccent)
                                    .padding(.vertical, 20)
                                Spacer()
                            }
                        }
                    }
                    
                    Spacer().frame(height: 80)
                }
                .padding(.top, 12)
            }
            .refreshable {
                await viewModel.loadCatalog(reset: true)
            }
        }
        .navigationTitle(viewModel.catalogName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView(viewModel: viewModel)
        }
        .task {
            if viewModel.items.isEmpty {
                await viewModel.loadCatalog(reset: true)
            }
        }
    }
    
    // MARK: - Header Bar (Search & Filter)
    private var headerBar: some View {
        HStack(spacing: 10) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.textTertiary)
                    .appFont(size: 14)
                
                TextField("\(L("In")) \(viewModel.catalogName) \(L("suchen..."))", text: $viewModel.searchQuery)
                    .appFont(size: 13)
                    .foregroundColor(AppTheme.textPrimary)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    #endif
                    .onSubmit {
                        Task {
                            await viewModel.loadCatalog(reset: true)
                        }
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    ClearFieldButton {
                        viewModel.searchQuery = ""
                        Task {
                            await viewModel.loadCatalog(reset: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.surface)
            )
            
            // Filter / Sort Button
            if viewModel.features?.sort != nil || viewModel.features?.filter != nil {
                Button(action: {
                    showFilterSheet = true
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .appFont(size: 24)
                            .foregroundColor(activeFilterCount > 0 ? AppTheme.cyanAccent : AppTheme.textSecondary)
                        
                        if activeFilterCount > 0 {
                            Circle()
                                .fill(AppTheme.secondaryAccent)
                                .frame(width: 8, height: 8)
                                .offset(x: 2, y: -2)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var activeFilterCount: Int {
        var count = viewModel.selectedFilters.count
        if viewModel.selectedSort != nil { count += 1 }
        return count
    }
    
    // MARK: - Loading Skeleton
    private var loadingGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<12, id: \.self) { _ in
                CardSkeletonView(width: 155, height: 220)
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.fill")
                .appFont(size: 40)
                .foregroundColor(AppTheme.textTertiary)
            
            Text(L("Keine Einträge gefunden"))
                .appFont(size: 16, weight: .bold)
                .foregroundColor(.white)
            
            if !viewModel.searchQuery.isEmpty || !viewModel.selectedFilters.isEmpty {
                Button(L("Filter zurücksetzen")) {
                    viewModel.resetFilters()
                }
                .appFont(size: 13, weight: .semibold)
                .foregroundColor(AppTheme.primaryAccent)
            }
        }
        .padding(.vertical, 60)
    }
}
