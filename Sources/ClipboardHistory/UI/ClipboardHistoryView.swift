import AppKit
import SwiftUI
import Combine

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    let historyStore: ClipboardHistoryStore
    let onClose: () -> Void
    let onRestore: (ClipboardEntry) -> Void
    let onUpdate: () -> Void

    @Published var searchText = ""
    @Published var selectedKind: ClipboardEntryKind?
    @Published var showClearListConfirmation = false
    @Published var showDetailPreview = false
    @Published var detailEntry: ClipboardEntry?
    @Published var historyIsFocused = false

    private var cancellables = Set<AnyCancellable>()

    init(
        historyStore: ClipboardHistoryStore,
        onClose: @escaping () -> Void,
        onRestore: @escaping (ClipboardEntry) -> Void,
        onUpdate: @escaping () -> Void = {}
    ) {
        self.historyStore = historyStore
        self.onClose = onClose
        self.onRestore = onRestore
        self.onUpdate = onUpdate
        selectedKind = nil

        historyStore.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.focusLatestIfNeeded()
            }
            .store(in: &cancellables)
    }

    var visibleEntries: [ClipboardEntry] {
        historyStore.entries.filter { entry in
            guard selectedKind == nil || entry.kind == selectedKind else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            return entry.preview.localizedCaseInsensitiveContains(query)
                || entry.fileNames.joined(separator: " ").localizedCaseInsensitiveContains(query)
                || entry.availableTypes.joined(separator: " ").localizedCaseInsensitiveContains(query)
        }
    }

    func onAppear() {
        focusLatest()
        historyIsFocused = true
    }

    func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            historyStore.moveSelection(by: -1, among: visibleEntries)
        case .down:
            historyStore.moveSelection(by: 1, among: visibleEntries)
        default:
            break
        }
    }

    func handleReturnKey() {
        guard let entry = historyStore.selectedEntry(in: visibleEntries) else { return }
        restore(entry)
    }

    func handleSpaceKey() {
        guard let entry = historyStore.selectedEntry(in: visibleEntries) else { return }
        detailEntry = entry
        showDetailPreview = true
    }

    func handleEscapeKey() {
        onClose()
    }

    func focusLatest() {
        historyStore.focusLatest()
    }

    private func focusLatestIfNeeded() {
        if historyStore.selectedEntryID == nil {
            focusLatest()
        }
    }

    func restore(_ entry: ClipboardEntry) {
        onRestore(entry)
    }

    func togglePin(_ entry: ClipboardEntry) {
        historyStore.togglePin(entry)
    }

    func delete(_ entry: ClipboardEntry) {
        historyStore.delete(entry)
    }

    func revealInFinder(_ entry: ClipboardEntry) {
    }

    func deleteSimilar(_ entry: ClipboardEntry) {
        let similarEntries = historyStore.entries.filter { $0.contentHash == entry.contentHash }
        for similarEntry in similarEntries {
            historyStore.delete(similarEntry)
        }
    }

    func clearList() {
        historyStore.clearAll(includePinned: true)
    }
}

struct ClipboardHistoryView: View {
    @StateObject var viewModel: ClipboardHistoryViewModel

    init(
        historyStore: ClipboardHistoryStore,
        onClose: @escaping () -> Void,
        onRestore: @escaping (ClipboardEntry) -> Void,
        onUpdate: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(
            wrappedValue: ClipboardHistoryViewModel(
                historyStore: historyStore,
                onClose: onClose,
                onRestore: onRestore,
                onUpdate: onUpdate
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if viewModel.visibleEntries.isEmpty {
                ContentUnavailableView(
                    viewModel.searchText.isEmpty ? "No Clipboard History" : "No Results",
                    systemImage: viewModel.searchText.isEmpty ? "clipboard" : "magnifyingglass",
                    description: Text(viewModel.searchText.isEmpty
                        ? "Copied items will appear here."
                        : "Try a different search term.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.visibleEntries) { entry in
                            ClipboardEntryRow(
                                entry: entry,
                                isLatest: entry == viewModel.visibleEntries.first,
                                isSelected: viewModel.historyStore.selectedEntryID == entry.id,
                                thumbnailLoader: viewModel.historyStore.thumbnail(for:)
                            ) {
                                viewModel.restore(entry)
                            }
                            .tag(entry.id)
                            .contextMenu { contextMenu(for: entry) }
                            .onTapGesture {
                                viewModel.historyStore.selectedEntryID = entry.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            viewModel.onAppear()
        }
        .onMoveCommand { direction in
            viewModel.handleMoveCommand(direction)
        }
        .onKeyPress(.return) {
            viewModel.handleReturnKey()
            return .handled
        }
        .onKeyPress(.space) {
            viewModel.handleSpaceKey()
            return .handled
        }
        .onExitCommand(perform: viewModel.onClose)
        .sheet(item: $viewModel.detailEntry, content: detailSheet)
        .alert("Clear Clipboard History?", isPresented: $viewModel.showClearListConfirmation) {
            Button("Clear List", role: .destructive) {
                viewModel.clearList()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all saved clipboard entries, including pinned items.")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                ZStack(alignment: .leading) {
                    Label("Clipboard History", systemImage: "clipboard")
                        .font(.headline)

                    // The hosting view consumes mouse events, so
                    // isMovableByWindowBackground alone cannot move this
                    // borderless panel. This transparent view starts the
                    // native NSWindow drag when the title is dragged.
                    WindowDragHandle()
                        .frame(width: 190, height: 28)
                }
                Spacer()
                Button(action: viewModel.onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Clipboard History")

                Button(action: viewModel.onUpdate) {
                    Label("Update List", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Add the current clipboard item to history")
            }

            TextField("Search clipboard", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search Clipboard History")

            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterButton("All", kind: nil)
                        ForEach([ClipboardEntryKind.text, .image, .file], id: \.self) { kind in
                            filterButton(kind.title, kind: kind)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 22)

                Button("Clear List", role: .destructive) {
                    viewModel.showClearListConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func filterButton(_ title: String, kind: ClipboardEntryKind?) -> some View {
        Button(title) {
            viewModel.selectedKind = kind
        }
        .buttonStyle(.bordered)
        .tint(viewModel.selectedKind == kind ? .accentColor : .secondary)
        .controlSize(.small)
    }

    private func detailSheet(for entry: ClipboardEntry) -> DetailPreviewView {
        let vm = DetailPreviewViewModel(
            entry: entry,
            historyStore: viewModel.historyStore,
            onRestore: viewModel.onRestore
        )
        vm.onDismiss = { viewModel.showDetailPreview = false; viewModel.detailEntry = nil }
        return DetailPreviewView(viewModel: vm)
    }

    @ViewBuilder
    private func contextMenu(for entry: ClipboardEntry) -> some View {
        Button("Copy") { viewModel.restore(entry) }
        Button("Preview") { viewModel.detailEntry = entry; viewModel.showDetailPreview = true }
        Button(entry.isPinned ? "Unpin" : "Pin") { viewModel.togglePin(entry) }
        Divider()
        if entry.kind == .file, !entry.fileNames.isEmpty {
            Button("Reveal in Finder") { viewModel.revealInFinder(entry) }
            Divider()
        }
        Button("Delete", role: .destructive) { viewModel.delete(entry) }
        Button("Delete All Similar") { viewModel.deleteSimilar(entry) }
    }
}

extension ClipboardEntryKind {
    var indicatorLetter: String {
        switch self {
        case .text: "T"
        case .image: "I"
        case .file: "F"
        case .link: "L"
        case .media: "M"
        case .data: "D"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .text: .blue
        case .image: .green
        case .file: .orange
        case .link: .purple
        case .media: .red
        case .data: .gray
        }
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleView {
        WindowDragHandleView()
    }

    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {}
}

private final class WindowDragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

@MainActor
final class ClipboardEntryRowViewModel: ObservableObject {
    let entry: ClipboardEntry
    let isLatest: Bool
    let isSelected: Bool
    let action: () -> Void
    private let thumbnailLoader: (ClipboardEntry) -> NSImage?

    @Published var thumbnail: NSImage? = nil

    init(
        entry: ClipboardEntry,
        isLatest: Bool,
        isSelected: Bool,
        thumbnailLoader: @escaping (ClipboardEntry) -> NSImage? = { entry in
            (try? DiskHistoryPersistence())?.loadThumbnail(for: entry)
        },
        action: @escaping () -> Void
    ) {
        self.entry = entry
        self.isLatest = isLatest
        self.isSelected = isSelected
        self.action = action
        self.thumbnailLoader = thumbnailLoader

        if entry.kind == .image {
            Task { [weak self, entry, thumbnailLoader] in
                if let thumb = thumbnailLoader(entry) {
                    self?.thumbnail = thumb
                }
            }
        }
    }

    var previewText: String {
        if entry.kind == .image || entry.kind == .media {
            if !entry.fileNames.isEmpty {
                return entry.fileNames[0]
            }
            return entry.kind == .image ? "Image" : "Media"
        }
        return entry.preview
    }
}

private struct ClipboardEntryRow: View {
    @StateObject var viewModel: ClipboardEntryRowViewModel

    init(
        entry: ClipboardEntry,
        isLatest: Bool,
        isSelected: Bool,
        thumbnailLoader: @escaping (ClipboardEntry) -> NSImage? = { entry in
            (try? DiskHistoryPersistence())?.loadThumbnail(for: entry)
        },
        action: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ClipboardEntryRowViewModel(
            entry: entry,
            isLatest: isLatest,
            isSelected: isSelected,
            thumbnailLoader: thumbnailLoader,
            action: action
        ))
    }

    var body: some View {
        Button(action: viewModel.action) {
            HStack(alignment: .center, spacing: 10) {
                if let thumbnail = viewModel.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(viewModel.entry.kind.indicatorLetter)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(viewModel.entry.kind.indicatorColor)
                        .frame(width: 42, height: 42)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.previewText)
                        .lineLimit(viewModel.entry.kind == .text ? 5 : 1)
                        .truncationMode(.tail)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(viewModel.isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(viewModel.isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(viewModel.entry.kind.title): \(viewModel.previewText)")
        .accessibilityHint("Press Return to copy this item to the clipboard")
    }
}

@MainActor
final class DetailPreviewViewModel: ObservableObject {
    let entry: ClipboardEntry
    let historyStore: ClipboardHistoryStore
    let onRestore: (ClipboardEntry) -> Void
    var onDismiss: (() -> Void)? = nil

    init(
        entry: ClipboardEntry,
        historyStore: ClipboardHistoryStore,
        onRestore: @escaping (ClipboardEntry) -> Void
    ) {
        self.entry = entry
        self.historyStore = historyStore
        self.onRestore = onRestore
    }

    func copy() {
        onRestore(entry)
        onDismiss?()
    }

    func dismiss() {
        onDismiss?()
    }

    func loadThumbnail() -> NSImage? {
        if let persistence = try? DiskHistoryPersistence() {
            return persistence.loadThumbnail(for: entry)
        }
        return nil
    }
}

struct DetailPreviewView: View {
    let viewModel: DetailPreviewViewModel

    init(viewModel: DetailPreviewViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    viewModel.copy()
                }
                .keyboardShortcut(.return)
                Button("Close") {
                    viewModel.dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(.regularMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let thumbnail = viewModel.loadThumbnail() {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 400, maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text(viewModel.entry.kind.indicatorLetter)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(viewModel.entry.kind.indicatorColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.entry.preview)
                            .font(.body)
                            .textSelection(.enabled)

                        Divider()

                        HStack(spacing: 16) {
                            Label(viewModel.entry.kind.title, systemImage: viewModel.entry.kind.symbolName)
                            if viewModel.entry.byteCount > 0 {
                                Label(ByteCountFormatter.string(fromByteCount: Int64(viewModel.entry.byteCount), countStyle: .file), systemImage: "doc")
                            }
                            if !viewModel.entry.fileNames.isEmpty {
                                Label("\(viewModel.entry.fileNames.count) file(s)", systemImage: "doc")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text("Copied \(viewModel.entry.lastUsedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if viewModel.entry.isPinned {
                            Label("Pinned", systemImage: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding()
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
    }
}
