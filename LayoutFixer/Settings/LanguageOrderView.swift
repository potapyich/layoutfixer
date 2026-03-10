import SwiftUI

/// Shows the user's ordered layout cycle and all available macOS layouts.
/// Layouts are classified into three tiers:
///   ✓ Full      — explicit mapping, letters + punctuation accurate
///   ◎ Partial   — QWERTY-compatible (auto-detected), letters accurate, punctuation may vary
///   ✗ None      — non-QWERTY, no mapping, cannot convert
struct LanguageOrderView: View {
    @Environment(AppSettings.self) var settings
    @State private var available: [LayoutInfo] = []
    @State private var supportMap: [String: LayoutSupport] = [:]

    private var inactive: [LayoutInfo] {
        available.filter { layout in
            !settings.activeLayouts.contains(where: { $0.id == layout.id })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            activeCycleSection
            if !inactive.isEmpty {
                Divider()
                availableSection
            }
        }
        .onAppear {
            available = InputSourceManager.shared.availableLayouts()
            // Build support map from the same call (cache is already warm)
            var map: [String: LayoutSupport] = [:]
            for layout in available {
                map[layout.id] = InputSourceManager.shared.support(for: layout.id)
            }
            supportMap = map
        }
    }

    // MARK: - Active cycle

    @ViewBuilder
    private var activeCycleSection: some View {
        Text("Active cycle").font(.headline)

        if settings.activeLayouts.isEmpty {
            Text("Add at least 2 layouts to enable conversion.")
                .foregroundStyle(.secondary).font(.caption)
        } else {
            activeList
        }
    }

    private var activeList: some View {
        VStack(spacing: 0) {
            ForEach(Array(settings.activeLayouts.enumerated()), id: \.element.id) { idx, layout in
                activeRow(layout: layout, idx: idx)
                if idx < settings.activeLayouts.count - 1 { Divider() }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }

    private func activeRow(layout: LayoutInfo, idx: Int) -> some View {
        HStack(spacing: 6) {
            Text(layout.flag).font(.title3)
            Text(layout.name).frame(maxWidth: .infinity, alignment: .leading)
            supportBadge(for: layout.id)

            Button { move(from: idx, by: -1) } label: { Image(systemName: "arrow.up") }
                .disabled(idx == 0).buttonStyle(.borderless)
            Button { move(from: idx, by: +1) } label: { Image(systemName: "arrow.down") }
                .disabled(idx == settings.activeLayouts.count - 1).buttonStyle(.borderless)
            Button { settings.activeLayouts.remove(at: idx) } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }.buttonStyle(.borderless)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
    }

    // MARK: - Available layouts

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available layouts").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(inactive.enumerated()), id: \.element.id) { idx, layout in
                    availableRow(layout: layout, idx: idx)
                    if idx < inactive.count - 1 { Divider() }
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        }
    }

    private func availableRow(layout: LayoutInfo, idx: Int) -> some View {
        HStack(spacing: 6) {
            Text(layout.flag).font(.title3)
            Text(layout.name).frame(maxWidth: .infinity, alignment: .leading)
            supportBadge(for: layout.id)
            Button { settings.activeLayouts.append(layout) } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
            }.buttonStyle(.borderless)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
    }

    // MARK: - Support badge

    @ViewBuilder
    private func supportBadge(for layoutID: String) -> some View {
        switch supportMap[layoutID] ?? .none {
        case .full:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Full conversion — letters and punctuation")
        case .qwerty:
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(.orange)
                .help("Partial — letters convert accurately; punctuation may be imprecise")
        case .none:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
                .help("Conversion not supported for this layout")
        }
    }

    // MARK: - Helpers

    private func move(from idx: Int, by delta: Int) {
        let dest = idx + delta
        guard dest >= 0, dest < settings.activeLayouts.count else { return }
        settings.activeLayouts.swapAt(idx, dest)
    }
}
