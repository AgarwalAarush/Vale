import SwiftUI

/// One quiet, discoverable context control; the Ready pill keeps its original size.
struct CurrentWorkContextChip: View {
    @ObservedObject var context: CurrentWorkContext
    private var title: String {
        if context.capturing { return "Reading screen…" }
        if context.screenAuthorized { return context.hasSelectionText ? "Screen & selected text" : "Current screen" }
        return context.hasSelectionText ? "Selected text · screen off" : "Enable screen context…"
    }
    var body: some View {
        Menu {
            CurrentWorkContextMenu(context: context)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: context.screenAuthorized ? "rectangle.dashed" : "rectangle.badge.plus")
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium))
            }.font(.system(size: 11.5)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 9).frame(height: 26)
                .background(Theme.fill.opacity(0.7)).clipShape(Capsule())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel(title).accessibilityIdentifier("vale.currentWorkContext")
            .help("Fresh screen and selected text are included when you ask. Choose context permissions or turn it off.")
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { context.refreshPermissions() }
    }
}

struct CurrentWorkContextMenu: View {
    @ObservedObject var context: CurrentWorkContext
    var body: some View {
        Toggle("Screen & selected text", isOn: Binding(get: { context.enabled }, set: { context.setEnabled($0) }))
        if context.enabled {
            if !context.screenAuthorized { Button("Allow screen access…") { context.requestScreenAccess() } }
            if !context.selectionAuthorized { Button("Allow selected text…") { context.requestSelectionAccess() } }
            Text("Added only when you ask. Vale is excluded.")
        }
    }
}

struct CurrentWorkContextSettings: View {
    @ObservedObject var context: CurrentWorkContext
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Context").font(.system(size: 13, weight: .semibold))
            Toggle("Screen & selected text", isOn: Binding(get: { context.enabled }, set: { context.setEnabled($0) })).toggleStyle(.switch)
            if context.enabled {
                HStack(spacing: 8) {
                    if !context.screenAuthorized { Button("Allow screen…") { context.requestScreenAccess() }.buttonStyle(.bordered) }
                    if !context.selectionAuthorized { Button("Allow selected text…") { context.requestSelectionAccess() }.buttonStyle(.bordered) }
                    if context.screenAuthorized && context.selectionAuthorized {
                        Label("Access allowed", systemImage: "checkmark").foregroundStyle(Theme.muted)
                    }
                }.controlSize(.small).font(.system(size: 12))
                Text("Added when you ask. A shared window takes priority.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.onAppear { context.refreshPermissions() }
    }
}
