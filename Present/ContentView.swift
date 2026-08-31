import SwiftUI

struct ContentView: View {
    @Bindable var state: PresentationState
    var server: RemoteServer
    @State private var selection: UUID?
    @State private var editingSlide: Slide?
    @State private var editingDisplayName: String = ""
    @State private var editingURL: String = ""
    @State private var editingText: String = ""
    @State private var editingIsText: Bool = false
    @State private var showingSetMenu = false
    @State private var newSetName: String = ""
    @State private var showingNewSetAlert = false
    @State private var showingRenameSetAlert = false
    @State private var renameSetName: String = ""
    @State private var showingRemoteInfo = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Toolbar con selector de sets
                VStack(spacing: 8) {
                    HStack {
                        Menu {
                            ForEach(state.presentationSets) { set in
                                Button(action: { state.switchToSet(id: set.id) }) {
                                    HStack {
                                        Text(set.name)
                                        if state.currentSetId == set.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(state.currentSet?.name ?? "No Set")
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.bordered)

                        Button(action: { showingNewSetAlert = true }) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)

                        Menu {
                            Button("Rename") {
                                renameSetName = state.currentSet?.name ?? ""
                                showingRenameSetAlert = true
                            }
                            if state.presentationSets.count > 1 {
                                Button("Delete", role: .destructive) {
                                    if let setId = state.currentSetId {
                                        state.deleteSet(id: setId)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.bordered)
                    }
                    .padding(8)
                }
                .background(Color(.controlBackgroundColor))

                // Lista de slides
                List(selection: $selection) {
                    ForEach(Array(state.slides.enumerated()), id: \.element.id) { index, slide in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                                .draggable(slide.id.uuidString)

                            if slide.isTextSlide {
                                Image(systemName: "text.alignleft")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .help("Text slide")
                            }

                            Text(slide.label)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button(action: { startEditing(slide) }) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .tag(slide.id)
                        .dropDestination(for: String.self) { items, _ in
                            guard let draggedIDString = items.first,
                                  let draggedID = UUID(uuidString: draggedIDString),
                                  let fromIndex = state.slides.firstIndex(where: { $0.id == draggedID }),
                                  let toIndex = state.slides.firstIndex(where: { $0.id == slide.id })
                            else { return false }
                            withAnimation {
                                state.moveSlide(from: IndexSet(integer: fromIndex), to: toIndex > fromIndex ? toIndex + 1 : toIndex)
                            }
                            return true
                        }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selection) { _, newValue in
                    if let newValue, let index = state.slides.firstIndex(where: { $0.id == newValue }) {
                        state.currentIndex = index
                    }
                }

                HStack {
                    Menu {
                        Button("URL Slide") { addSlide() }
                        Button("Text Slide") { addTextSlide() }
                    } label: {
                        Image(systemName: "plus")
                    } primaryAction: {
                        addSlide()
                    }
                    .menuStyle(.button)
                    .frame(width: 46)
                    .help("Add a slide")

                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    .help("Remove the selected slide")
                    Spacer()
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 250, max: 500)
        } detail: {
            if let slide = state.currentSlide {
                WebView(content: slide.content, pageZoom: state.zoomLevel, scroll: state.scrollRequest)
            } else {
                VStack {
                    Text("No slide selected")
                        .foregroundStyle(.secondary)
                    Text("Add a URL to get started")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(windowTitle)
        .onReceive(NotificationCenter.default.publisher(for: .showRemoteInfo)) { _ in
            showingRemoteInfo = true
        }
        .sheet(isPresented: $showingRemoteInfo) {
            RemoteControlView(
                server: server,
                onToggle: { server.toggle(state: state) },
                onClose: { showingRemoteInfo = false }
            )
        }
        .onAppear {
            if state.slides.isEmpty {
                addSlide()
            }
            if let first = state.slides.first {
                selection = first.id
            }
        }
        .sheet(item: $editingSlide) { slide in
            EditSlideSheet(
                displayName: $editingDisplayName,
                url: $editingURL,
                text: $editingText,
                isText: $editingIsText,
                onSave: { saveSlideEdits(slide) },
                onCancel: { editingSlide = nil }
            )
        }
        .alert("New Presentation List", isPresented: $showingNewSetAlert) {
            TextField("Name", text: $newSetName)
            Button("Create") {
                if !newSetName.trimmingCharacters(in: .whitespaces).isEmpty {
                    state.createSet(name: newSetName)
                    newSetName = ""
                }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Rename Presentation List", isPresented: $showingRenameSetAlert) {
            TextField("Name", text: $renameSetName)
            Button("Rename") {
                if let setId = state.currentSetId, !renameSetName.trimmingCharacters(in: .whitespaces).isEmpty {
                    state.renameSet(id: setId, newName: renameSetName)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    /// The list name, plus the standard "Edited" marker once the list has
    /// drifted from the file it came from.
    private var windowTitle: String {
        let name = state.currentSet?.name ?? "Present"
        return state.hasUnsavedFileChanges ? "\(name) — Edited" : name
    }

    private func startEditing(_ slide: Slide) {
        editingSlide = slide
        editingDisplayName = slide.displayName ?? ""
        editingURL = slide.url
        editingText = slide.text ?? ""
        editingIsText = slide.isTextSlide
    }

    private func saveSlideEdits(_ slide: Slide) {
        let name = editingDisplayName.trimmingCharacters(in: .whitespaces)
        state.updateSlide(
            slide,
            url: editingURL,
            displayName: name.isEmpty ? nil : name,
            text: editingIsText ? editingText : nil
        )
        editingSlide = nil
    }

    private func addSlide() {
        append(Slide())
    }

    private func addTextSlide() {
        let slide = Slide.textSlide("# New slide")
        append(slide)
        startEditing(slide)
    }

    private func append(_ slide: Slide) {
        state.addSlide(slide)
        selection = slide.id
        state.currentIndex = state.slides.count - 1
    }

    private func deleteSelected() {
        guard let selection else { return }
        if let index = state.slides.firstIndex(where: { $0.id == selection }) {
            state.removeSlide(at: index)
            if state.slides.isEmpty {
                self.selection = nil
                state.currentIndex = 0
            } else {
                let newIndex = min(index, state.slides.count - 1)
                state.currentIndex = newIndex
                self.selection = state.slides[newIndex].id
            }
        }
    }
}

struct EditSlideSheet: View {
    @Binding var displayName: String
    @Binding var url: String
    @Binding var text: String
    @Binding var isText: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    private var canSave: Bool {
        let field = isText ? text : url
        return !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Slide")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Display Name (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g., Introduction", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("", selection: $isText) {
                Text("URL").tag(false)
                Text("Text").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Markdown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(.separatorColor))
                        )
                    Text("# Heading  ·  **bold**  ·  *italic*  ·  - bullet  ·  `code`")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://example.com", text: $url)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: isText ? 420 : 260)
    }
}
