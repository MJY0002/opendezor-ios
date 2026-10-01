import SwiftUI

public struct FilterSheetView: View {
    @ObservedObject var viewModel: CatalogViewModel
    @Environment(\.dismiss) private var dismiss
    
    public init(viewModel: CatalogViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Sort Options
                        if let sorts = viewModel.features?.sort, !sorts.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L("Sortierung"))
                                    .appFont(size: 15, weight: .bold)
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                                    ForEach(sorts) { sort in
                                        let isSelected = viewModel.selectedSort == sort.id
                                        Button(action: {
                                            if isSelected {
                                                viewModel.applySort(nil)
                                            } else {
                                                viewModel.applySort(sort.id)
                                            }
                                        }) {
                                            HStack {
                                                Text(sort.name?.value ?? sort.id)
                                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                                    .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                                                if isSelected {
                                                    Image(systemName: "checkmark")
                                                        .appFont(size: 11, weight: .bold)
                                                        .foregroundColor(.white)
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(isSelected ? AppTheme.primaryAccent : AppTheme.surfaceLight)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Filters List
                        if let filters = viewModel.features?.filter, !filters.isEmpty {
                            ForEach(filters) { filter in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(filter.name?.value ?? filter.id)
                                        .appFont(size: 15, weight: .bold)
                                        .foregroundColor(AppTheme.textPrimary)
                                    
                                    if let values = filter.values {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                            ForEach(values, id: \.self) { val in
                                                let isSelected = viewModel.selectedFilters[filter.id] == val.keyString
                                                Button(action: {
                                                    if isSelected {
                                                        viewModel.setFilter(id: filter.id, value: nil)
                                                    } else {
                                                        viewModel.setFilter(id: filter.id, value: val.keyString)
                                                    }
                                                }) {
                                                    HStack {
                                                        Text(val.displayTitle)
                                                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                                            .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .background(
                                                        Capsule()
                                                            .fill(isSelected ? AppTheme.cyanAccent : AppTheme.surfaceLight)
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(L("Filter & Sortierung"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Zurücksetzen")) {
                        viewModel.resetFilters()
                    }
                    .foregroundColor(AppTheme.destructive)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Fertig")) {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.primaryAccent)
                }
            }
        }
    }
}
