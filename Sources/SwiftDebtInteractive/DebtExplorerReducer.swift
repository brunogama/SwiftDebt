import Foundation
import SwiftDebtCore

public enum DebtExplorerAction: Equatable, Sendable {
    case moveSelection(Int)
    case selectVisibleItem(offset: Int)
    case selectItem(id: String)
    case setPriorityFilter(Priority?)
    case cyclePriorityFilter
    case setSearchQuery(String)
    case clearFilters
}

public struct DebtExplorerState: Equatable, Sendable {
    public let items: [RankedDebtItem]
    public let visibleItemIDs: [String]
    public let selectedItemID: String?
    public let selectedVisibleIndex: Int
    public let priorityFilter: Priority?
    public let searchQuery: String

    public init(analysis: RankedDebtAnalysis) {
        self.items = analysis.items
        self.priorityFilter = nil
        self.searchQuery = ""
        self.visibleItemIDs = Self.visibleItemIDs(in: analysis.items, priorityFilter: nil, searchQuery: "")
        self.selectedVisibleIndex = 0
        self.selectedItemID = visibleItemIDs.first
    }

    private init(
        items: [RankedDebtItem],
        visibleItemIDs: [String],
        selectedVisibleIndex: Int,
        selectedItemID: String?,
        priorityFilter: Priority?,
        searchQuery: String
    ) {
        self.items = items
        self.visibleItemIDs = visibleItemIDs
        self.selectedVisibleIndex = selectedVisibleIndex
        self.selectedItemID = selectedItemID
        self.priorityFilter = priorityFilter
        self.searchQuery = searchQuery
    }

    public var selectedItem: RankedDebtItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.item.id == selectedItemID }
    }

    public func selectedDetail(editor: String? = nil) -> DebtExplorerDetail? {
        guard let selectedItem else { return nil }
        return DebtExplorerDetail(item: selectedItem, editor: editor)
    }

    fileprivate func movingSelection(by delta: Int) -> DebtExplorerState {
        guard !visibleItemIDs.isEmpty else {
            return replacingSelection(index: 0, selectedID: nil)
        }
        let bounded = max(0, min(visibleItemIDs.count - 1, selectedVisibleIndex + delta))
        return replacingSelection(index: bounded, selectedID: visibleItemIDs[bounded])
    }

    fileprivate func selectingVisibleItem(offset: Int) -> DebtExplorerState {
        guard !visibleItemIDs.isEmpty else {
            return replacingSelection(index: 0, selectedID: nil)
        }
        let bounded = max(0, min(visibleItemIDs.count - 1, offset))
        return replacingSelection(index: bounded, selectedID: visibleItemIDs[bounded])
    }

    fileprivate func selectingItem(id: String) -> DebtExplorerState {
        guard let index = visibleItemIDs.firstIndex(of: id) else { return self }
        return replacingSelection(index: index, selectedID: id)
    }

    fileprivate func replacingFilters(priority: Priority?, query: String) -> DebtExplorerState {
        let visible = Self.visibleItemIDs(in: items, priorityFilter: priority, searchQuery: query)
        let retainedIndex = selectedItemID.flatMap { visible.firstIndex(of: $0) }
        let index = retainedIndex ?? 0
        return DebtExplorerState(
            items: items,
            visibleItemIDs: visible,
            selectedVisibleIndex: visible.isEmpty ? 0 : index,
            selectedItemID: visible.isEmpty ? nil : visible[index],
            priorityFilter: priority,
            searchQuery: query
        )
    }

    private func replacingSelection(index: Int, selectedID: String?) -> DebtExplorerState {
        DebtExplorerState(
            items: items,
            visibleItemIDs: visibleItemIDs,
            selectedVisibleIndex: index,
            selectedItemID: selectedID,
            priorityFilter: priorityFilter,
            searchQuery: searchQuery
        )
    }

    private static func visibleItemIDs(
        in items: [RankedDebtItem],
        priorityFilter: Priority?,
        searchQuery: String
    ) -> [String] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.compactMap { item in
            if let priorityFilter, item.score.priority != priorityFilter { return nil }
            guard !query.isEmpty else { return item.item.id }
            return item.matchesDebtExplorerQuery(query) ? item.item.id : nil
        }
    }
}

public enum DebtExplorerReducer {
    public static func reduce(_ state: DebtExplorerState, _ action: DebtExplorerAction) -> DebtExplorerState {
        switch action {
        case .moveSelection(let delta):
            return state.movingSelection(by: delta)
        case .selectVisibleItem(let offset):
            return state.selectingVisibleItem(offset: offset)
        case .selectItem(let id):
            return state.selectingItem(id: id)
        case .setPriorityFilter(let priority):
            return state.replacingFilters(priority: priority, query: state.searchQuery)
        case .cyclePriorityFilter:
            return state.replacingFilters(priority: nextPriority(after: state.priorityFilter), query: state.searchQuery)
        case .setSearchQuery(let query):
            return state.replacingFilters(priority: state.priorityFilter, query: query)
        case .clearFilters:
            return state.replacingFilters(priority: nil, query: "")
        }
    }

    private static func nextPriority(after priority: Priority?) -> Priority? {
        switch priority {
        case nil: return .critical
        case .critical: return .high
        case .high: return .medium
        case .medium: return .low
        case .low: return nil
        }
    }
}

private extension RankedDebtItem {
    func matchesDebtExplorerQuery(_ query: String) -> Bool {
        let fields = [
            item.id,
            item.entity.displayName,
            item.entity.location.file ?? "",
            category,
            explanation,
            recommendation,
        ]
        if fields.contains(where: { $0.lowercased().contains(query) }) { return true }
        return item.evidence.contains { evidence in
            evidence.kind.lowercased().contains(query)
                || evidence.rawValue.lowercased().contains(query)
                || (evidence.note?.lowercased().contains(query) ?? false)
        }
    }
}
