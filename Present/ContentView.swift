import SwiftUI

struct ContentView: View {
    @Bindable var state: PresentationState
    @State private var selection: UUID?
    @State private var editingSlide: Slide?
    @State private var editingDisplayName: String = ""
    @State private var editingURL: String = ""
    @State private var showingSetMenu = false
    @State private var newSetName: String = ""
    @State private var showingNewSetAlert = false
    @State private var showingRenameSetAlert = false
    @State private var renameSetName: String = ""

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
                    Button(action: addSlide) {
                        Image(systemName: "plus")
                    }
                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    Spacer()
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 250, max: 500)
        } detail: {
            if let slide = state.currentSlide {
                WebView(url: slide.url, pageZoom: state.zoomLevel)
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
                slide: slide,
                displayName: $editingDisplayName,
                url: $editingURL,
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

    private func startEditing(_ slide: Slide) {
        editingSlide = slide
        editingDisplayName = slide.displayName ?? ""
        editingURL = slide.url
    }

    private func saveSlideEdits(_ slide: Slide) {
        let name = editingDisplayName.trimmingCharacters(in: .whitespaces)
        state.updateSlide(slide, url: editingURL, displayName: name.isEmpty ? nil : name)
        editingSlide = nil
    }

    private func addSlide() {
        let slide = Slide()
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
    let slide: Slide
    @Binding var displayName: String
    @Binding var url: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Edit Slide")
                    .font(.headline)

                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Display Name (optional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., Introduction", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://example.com", text: $url)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding()

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            Spacer()
        }
        .frame(minWidth: 400, minHeight: 250)
    }
}
