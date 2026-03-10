/// Determines the source→target layout pair for the current hotkey press.
///
/// Cycle rules:
/// - Source = current macOS input source (or first in list if not found).
/// - Target = next layout in the user's ordered list that has a known mapping.
///   Layouts without a mapping are **skipped** during cycling so the
///   conversion always produces a meaningful result.
/// - If no valid target exists (e.g. list has only unmapped layouts) → returns nil.
struct LayoutCycleManager {

    struct Pair {
        let sourceID: String
        let targetID: String
        let target: LayoutInfo
    }

    func currentPair(settings: AppSettings) -> Pair? {
        let active = settings.activeLayouts
        guard active.count >= 2 else { return nil }

        let currentID = InputSourceManager.shared.currentLayoutID() ?? ""
        let sourceIdx = active.firstIndex(where: { $0.id == currentID }) ?? 0

        // Walk forward from sourceIdx to find the next layout with conversion support.
        // Both .full and .qwerty tiers are usable; .none (non-QWERTY, no mapping) is skipped.
        for offset in 1..<active.count {
            let candidateIdx = (sourceIdx + offset) % active.count
            let candidate = active[candidateIdx]
            if InputSourceManager.shared.support(for: candidate.id) != .none {
                return Pair(
                    sourceID: active[sourceIdx].id,
                    targetID: candidate.id,
                    target:   candidate
                )
            }
        }
        return nil  // no valid target found
    }
}
