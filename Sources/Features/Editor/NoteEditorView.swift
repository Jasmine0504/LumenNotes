import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

@MainActor
struct NoteEditorView: View {
    @Environment(FontTheme.self) private var theme
    @Environment(LockService.self) private var lockService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var note: Note

    let onOpenNote: (UUID) -> Void

    @State private var document = NoteDocument.empty
    @State private var loaded = false
    @State private var richContext = RichTextEditingContext()
    @State private var activeBlockID: UUID?
    @State private var saveTask: Task<Void, Never>?
    @State private var isSaving = false
    @State private var isDeleting = false

    @State private var showFontPanel = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var scanFromPhoto = false
    @State private var showFileImporter = false
    @State private var showLinkSheet = false
    @State private var showMapSheet = false
    @State private var showScanner = false
    @State private var showInternalLinkPicker = false
    @State private var drawingBlockID: UUID?
    @State private var previewSelection: AttachmentSelection?
    @State private var attachmentToDelete: Attachment?
    @State private var showDeleteAttachmentAlert = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showLockError = false
    @State private var showDeleteNoteAlert = false
    @State private var openPhotoAfterScanAlert = false

    @State private var recorder = VoiceRecorder()
    @State private var liveBlockID: UUID?
    @State private var liveMarker = ""
    @State private var isStartingRecording = false
    @State private var isStoppingRecording = false

    var body: some View {
        Group {
            if note.isLocked {
                LockGateView(note: note)
            } else {
                editor
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !note.isLocked {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showFontPanel = true
                    } label: {
                        Image(systemName: "textformat.size")
                    }
                    .accessibilityLabel("字体与字号")

                    Button {
                        lockNote()
                    } label: {
                        Image(systemName: "lock.open")
                    }
                    .accessibilityLabel("锁定备忘录")

                    Menu {
                        ShareLink(item: exportText) {
                            Label("导出纯文本", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showDeleteNoteAlert = true
                        } label: {
                            Label("删除备忘录", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showFontPanel) {
            FontSettingsView(note: note)
                .environment(theme)
        }
        .sheet(isPresented: $showLinkSheet) {
            LinkAttachmentSheet { url, title in
                addAttachment(AttachmentFactory.link(url: url, title: title))
            }
        }
        .sheet(isPresented: $showMapSheet) {
            MapAttachmentSheet { name, latitude, longitude in
                addAttachment(AttachmentFactory.map(title: name, latitude: latitude, longitude: longitude))
            }
        }
        .sheet(isPresented: Binding(
            get: { drawingBlockID != nil },
            set: { presented in
                if !presented {
                    let id = drawingBlockID
                    drawingBlockID = nil
                    recognizeDrawing(id: id)
                }
            }
        )) {
            if let id = drawingBlockID {
                DrawingEditorSheet(drawingData: Binding(
                    get: { block(for: id)?.drawingData },
                    set: { value in
                        updateBlock(id) { $0.drawingData = value }
                        scheduleSave()
                    }
                ))
            }
        }
        .sheet(isPresented: $showInternalLinkPicker) {
            InternalLinkPicker(currentNoteID: note.id) { target in
                let block = NoteBlock.internalLink(noteID: target.id, title: target.displayTitle)
                insertBlock(block, after: activeBlockID)
            }
        }
        .sheet(item: $previewSelection) { selection in
            AttachmentPreviewView(attachment: selection.attachment)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handlePDFImport(result)
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView(
                onComplete: { images in
                    showScanner = false
                    Task { await addScan(images: images) }
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .alert("无法完成", isPresented: $showError) {
            Button("好", role: .cancel) {
                if openPhotoAfterScanAlert {
                    openPhotoAfterScanAlert = false
                    scanFromPhoto = true
                    showPhotoPicker = true
                }
            }
        } message: {
            Text(errorMessage)
        }
        .alert("锁定失败", isPresented: $showLockError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(lockService.lastError ?? "未知错误")
        }
        .alert("删除附件？", isPresented: $showDeleteAttachmentAlert, presenting: attachmentToDelete) { attachment in
            Button("删除", role: .destructive) { deleteAttachment(attachment) }
            Button("取消", role: .cancel) { attachmentToDelete = nil }
        } message: { _ in
            Text("附件会从这条备忘录中移除。")
        }
        .alert("删除备忘录？", isPresented: $showDeleteNoteAlert) {
            Button("删除", role: .destructive) {
                isDeleting = true
                modelContext.delete(note)
                try? modelContext.save()
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可撤销。")
        }
        .onAppear {
            loadIfNeeded()
        }
        .onChange(of: note.isLocked) { _, locked in
            if locked {
                document = .empty
                activeBlockID = nil
            } else {
                loadIfNeeded(force: true)
            }
        }
        .onChange(of: document) { _, _ in
            guard loaded else { return }
            scheduleSave()
        }
        .onChange(of: recorder.displayText) { _, text in
            guard liveBlockID != nil else { return }
            updateLiveBlock(text: text)
        }
        .onChange(of: recorder.errorMessage) { _, message in
            if let message, !message.isEmpty {
                presentError(message)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                persistNow()
            }
        }
        .onChange(of: photoItem) { _, _ in
            handlePhotoSelection()
        }
        .onDisappear {
            saveTask?.cancel()
            persistNow()
            if recorder.isRecording || recorder.isPreparing { recorder.cancel() }
        }
        .userActivity("com.lumen.notes.note") { activity in
            activity.title = note.displayTitle
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.targetContentIdentifier = "note/\(note.id.uuidString)"
            activity.userInfo = [
                "noteID": note.id.uuidString,
                "url": "lumen://note/\(note.id.uuidString)"
            ]
        }
    }

    private var editor: some View {
        ZStack {
            LumenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleSection
                    blockList
                        .id(dynamicTypeSize)
                    editorFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if recorder.isRecording || recorder.isPreparing {
                    RecordingPanel(
                        recorder: recorder,
                        onPause: { recorder.pause() },
                        onResume: { recorder.resume() },
                        onStop: { Task { await stopRecording() } },
                        onCancel: { cancelRecording() }
                    )
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 14)
                }
                NoteEditorToolbar(
                    richContext: richContext,
                    isRecording: recorder.isRecording,
                    onStyle: applyStyle,
                    onInsert: handleInsert,
                    onAudio: { Task { await toggleRecording() } },
                    onDismissKeyboard: dismissKeyboard
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField(
                "",
                text: $note.title,
                prompt: Text("标题")
                    .font(theme.font(for: .title).weight(.semibold))
                    .foregroundStyle(.tertiary),
                axis: .vertical
            )
            .font(theme.font(for: .title).weight(.semibold))
            .textFieldStyle(.plain)
            .foregroundStyle(.primary)
            .onChange(of: note.title) { _, _ in
                note.touch()
                scheduleSave()
            }

            HStack(spacing: 8) {
                Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(theme.font(for: .caption))
                    .foregroundStyle(.secondary)
                if let folder = note.folder {
                    Text("· \(folder.name)")
                        .font(theme.font(for: .caption))
                        .foregroundStyle(.secondary)
                }
                if !note.attachments.isEmpty {
                    Text("· \(note.attachments.count) 个附件")
                        .font(theme.font(for: .caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSaving {
                    Text("已保存")
                        .font(theme.font(for: .caption))
                        .foregroundStyle(.secondary)
                }
            }

            if !note.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(note.tags), id: \.id) { tag in
                            TagChip(name: tag.name)
                        }
                    }
                }
            }

            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.45))
                .frame(height: 0.5)
                .padding(.top, 2)
        }
    }

    private var blockList: some View {
        ForEach(blockEntries, id: \.block.id) { entry in
            NoteBlockRow(
                block: binding(for: entry.block.id),
                attachments: note.attachments,
                fontOverride: note.fontOverride,
                richContext: richContext,
                listNumber: entry.number,
                canCollapse: canCollapse(entry.block),
                onTyping: scheduleSave,
                onFocus: { activeBlockID = entry.block.id },
                onRequestInternalLink: {
                    activeBlockID = entry.block.id
                    showInternalLinkPicker = true
                },
                onToggleCollapse: {
                    toggleCollapse(entry.block.id)
                },
                onDelete: {
                    deleteBlock(entry.block.id)
                },
                onOpenDrawing: {
                    drawingBlockID = entry.block.id
                },
                onPreviewAttachment: { attachment in
                    previewSelection = AttachmentSelection(attachment: attachment)
                },
                onDeleteAttachment: { attachment in
                    attachmentToDelete = attachment
                    showDeleteAttachmentAlert = true
                },
                onOpenInternalLink: { id in
                    onOpenNote(id)
                }
            )
        }
    }

    private var editorFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw")
            Text("点击工具栏 + 插入核对清单、表格、速绘或附件；输入 #标签 会自动归档，输入 >> 可关联另一条备忘录。")
                .font(theme.font(for: .caption))
        }
        .foregroundStyle(.tertiary)
        .padding(.top, 14)
    }

    // MARK: - Loading and saving

    private func loadIfNeeded(force: Bool = false) {
        guard !note.isLocked else { return }
        guard force || !loaded else { return }
        var value = note.document
        if value.blocks.isEmpty { value = .empty }
        document = value
        loaded = true
        activeBlockID = nil
    }

    private func scheduleSave() {
        saveTask?.cancel()
        isSaving = true
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            persistNow()
        }
    }

    private func persistNow() {
        guard loaded, !note.isLocked, !isDeleting else { return }
        note.document = document
        syncTags()
        note.drawingSearchText = document.blocks.compactMap(\.drawingText).joined(separator: "\n")
        note.touch()
        try? modelContext.save()
        isSaving = false
    }

    private func syncTags() {
        let names = SearchService.extractTags(from: document.searchableText)
        guard let existing = try? modelContext.fetch(FetchDescriptor<Tag>()) else { return }
        var byName: [String: Tag] = [:]
        for tag in existing { byName[tag.name] = tag }
        var resolved: [Tag] = []
        for name in names {
            if let tag = byName[name] {
                resolved.append(tag)
            } else {
                let tag = Tag(name: name)
                modelContext.insert(tag)
                byName[name] = tag
                resolved.append(tag)
            }
        }
        note.tags = resolved
    }

    // MARK: - Block operations

    private struct BlockEntry {
        let block: NoteBlock
        let number: Int?
    }

    private var blockEntries: [BlockEntry] {
        let hidden = document.hiddenBlockIDs()
        var number = 0
        var entries: [BlockEntry] = []
        for block in document.blocks where !hidden.contains(block.id) {
            if block.kind == .heading {
                number = 0
            } else if block.kind == .paragraph, (block.listStyle ?? .body) == .numbered {
                number += 1
            } else if block.kind == .paragraph {
                number = 0
            } else {
                number = 0
            }
            entries.append(BlockEntry(block: block, number: number == 0 ? nil : number))
        }
        return entries
    }

    private func binding(for id: UUID) -> Binding<NoteBlock> {
        Binding(
            get: {
                document.blocks.first { $0.id == id } ?? NoteBlock.paragraph()
            },
            set: { newValue in
                guard let index = document.blocks.firstIndex(where: { $0.id == id }) else { return }
                document.blocks[index] = newValue
            }
        )
    }

    private func block(for id: UUID) -> NoteBlock? {
        document.blocks.first { $0.id == id }
    }

    private func updateBlock(_ id: UUID, mutate: (inout NoteBlock) -> Void) {
        guard let index = document.blocks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&document.blocks[index])
    }

    private func insertBlock(_ block: NoteBlock, after id: UUID?) {
        var value = document
        let anchor = id ?? activeBlockID ?? document.blocks.last?.id
        value.insert(block, after: anchor)
        document = value
        activeBlockID = block.id
        scheduleSave()
    }

    private func deleteBlock(_ id: UUID) {
        document.remove(id: id)
        if activeBlockID == id { activeBlockID = nil }
        scheduleSave()
    }

    private func canCollapse(_ block: NoteBlock) -> Bool {
        guard block.kind == .heading,
              let index = document.blocks.firstIndex(where: { $0.id == block.id }) else { return false }
        let level = block.headingLevel ?? 1
        for next in document.blocks.dropFirst(index + 1) {
            if next.kind == .heading, (next.headingLevel ?? 1) <= level { return false }
            return true
        }
        return false
    }

    private func toggleCollapse(_ id: UUID) {
        updateBlock(id) { block in
            block.isCollapsed = !(block.isCollapsed ?? false)
        }
        scheduleSave()
    }

    private func applyStyle(_ command: BlockStyleCommand) {
        guard let id = activeBlockID else {
            presentError("先点一下要设置样式的正文。")
            return
        }
        guard let block = block(for: id),
              (block.kind == .heading || block.kind == .paragraph) else {
            presentError("只能给标题或正文设置段落样式。")
            return
        }
        updateBlock(id) { block in
            switch command {
            case .heading(let level):
                block.kind = .heading
                block.headingLevel = min(3, max(1, level))
                block.isCollapsed = false
                block.listStyle = nil
            case .paragraph(let style):
                block.kind = .paragraph
                block.listStyle = style
                block.headingLevel = nil
                block.isCollapsed = nil
            }
        }
        scheduleSave()
    }

    private func handleInsert(_ command: InsertCommand) {
        switch command {
        case .checklist:
            insertBlock(.checklist(), after: activeBlockID)
            dismissKeyboard()
        case .table:
            insertBlock(.table(), after: activeBlockID)
            dismissKeyboard()
        case .drawing:
            let block = NoteBlock.drawing()
            insertBlock(block, after: activeBlockID)
            drawingBlockID = block.id
        case .photo:
            scanFromPhoto = false
            showPhotoPicker = true
        case .pdf:
            showFileImporter = true
        case .scan:
            if VNDocumentCameraViewController.isSupported {
                showScanner = true
            } else {
                openPhotoAfterScanAlert = true
                presentError("当前设备没有可用的相机扫描器。请选择一张照片，流明笔记会用 Vision OCR 生成可搜索的 PDF。")
            }
        case .link:
            showLinkSheet = true
        case .map:
            showMapSheet = true
        case .internalLink:
            showInternalLinkPicker = true
        }
    }

    // MARK: - Attachments

    private func addAttachment(_ attachment: Attachment, after id: UUID? = nil) {
        modelContext.insert(attachment)
        note.attachments.append(attachment)
        note.touch()
        let block = NoteBlock.attachment(attachment.id)
        insertBlock(block, after: id ?? activeBlockID)
        try? modelContext.save()
    }

    private func handlePhotoSelection() {
        guard let item = photoItem else { return }
        let wantsScan = scanFromPhoto
        Task {
            guard let loaded = try? await item.loadTransferable(type: Data.self),
                  let data = loaded,
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    photoItem = nil
                    scanFromPhoto = false
                    presentError("无法读取这张照片。")
                }
                return
            }
            if wantsScan {
                let attachment = await AttachmentFactory.scan(images: [image])
                await MainActor.run {
                    addAttachment(attachment)
                    photoItem = nil
                    scanFromPhoto = false
                }
            } else {
                let jpeg = image.jpegData(compressionQuality: 0.88) ?? data
                await MainActor.run {
                    addAttachment(AttachmentFactory.photo(data: jpeg, fileName: "照片 \(Self.shortDate()).jpg"))
                    photoItem = nil
                    scanFromPhoto = false
                }
            }
        }
    }

    private func handlePDFImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                presentError("无法读取这个 PDF。")
                return
            }
            let attachment = AttachmentFactory.pdf(data: data, fileName: url.lastPathComponent)
            addAttachment(attachment)
        case .failure(let error):
            presentError(error.localizedDescription)
        }
    }

    private func addScan(images: [UIImage]) async {
        guard !images.isEmpty else { return }
        let attachment = await AttachmentFactory.scan(images: images)
        await MainActor.run {
            addAttachment(attachment)
        }
    }

    private func deleteAttachment(_ attachment: Attachment) {
        note.attachments.removeAll { $0.id == attachment.id }
        modelContext.delete(attachment)
        document.blocks.removeAll { $0.attachmentID == attachment.id }
        attachmentToDelete = nil
        try? modelContext.save()
        scheduleSave()
    }

    private func recognizeDrawing(id: UUID?) {
        guard let id else { return }
        guard let data = block(for: id)?.drawingData else { return }
        Task {
            let text = await OCRService.drawingText(data: data)
            await MainActor.run {
                updateBlock(id) { $0.drawingText = text }
                note.drawingSearchText = document.blocks.compactMap(\.drawingText).joined(separator: "\n")
                persistNow()
            }
        }
    }

    // MARK: - Recording

    private func toggleRecording() async {
        if recorder.isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard !isStartingRecording, !recorder.isRecording else { return }
        isStartingRecording = true
        await recorder.start()
        isStartingRecording = false
        if recorder.isRecording {
            liveMarker = "[00:00] "
            let block = NoteBlock.paragraph(liveMarker)
            insertBlock(block, after: activeBlockID)
            liveBlockID = block.id
            updateLiveBlock(text: recorder.displayText)
        }
    }

    private func stopRecording() async {
        guard recorder.isRecording, !isStoppingRecording else { return }
        isStoppingRecording = true
        let result = await recorder.stop()
        isStoppingRecording = false
        let anchor = liveBlockID
        liveBlockID = nil
        liveMarker = ""
        if let result, !result.data.isEmpty {
            let attachment = AttachmentFactory.audio(
                data: result.data,
                duration: result.duration,
                transcript: result.transcript
            )
            addAttachment(attachment, after: anchor)
        }
        persistNow()
    }

    private func cancelRecording() {
        recorder.cancel()
        if let liveBlockID {
            document.remove(id: liveBlockID)
        }
        liveBlockID = nil
        liveMarker = ""
        persistNow()
    }

    private func updateLiveBlock(text: String) {
        guard let id = liveBlockID else { return }
        updateBlock(id) { block in
            block.text = .text(liveMarker + text)
        }
        scheduleSave()
    }

    // MARK: - Lock and misc

    private func lockNote() {
        persistNow()
        lockService.lock(note: note, context: modelContext)
        if note.isLocked {
            document = .empty
            activeBlockID = nil
        } else {
            showLockError = true
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private var exportText: String {
        var pieces = [note.displayTitle, ""]
        for block in document.blocks {
            switch block.kind {
            case .heading:
                pieces.append(String(repeating: "#", count: block.headingLevel ?? 1) + " " + (block.text?.plain ?? ""))
            case .paragraph:
                pieces.append(block.text?.plain ?? "")
            case .checklist:
                for item in block.checklistItems ?? [] {
                    pieces.append("- [\(item.isChecked ? "x" : " ")] \(item.text)")
                }
            case .table:
                for row in block.table?.rows ?? [] {
                    pieces.append("| " + row.joined(separator: " | ") + " |")
                }
            case .drawing:
                pieces.append("[速绘] \(block.drawingText ?? "")")
            case .attachment:
                if let title = block.internalLinkTitle {
                    pieces.append("→ \(title)")
                } else if let id = block.attachmentID,
                          let attachment = note.attachments.first(where: { $0.id == id }) {
                    pieces.append("[\(attachment.kind.displayName)] \(attachment.fileName)")
                    if !attachment.ocrText.isEmpty { pieces.append(attachment.ocrText) }
                }
            }
        }
        return pieces.joined(separator: "\n")
    }

    private static func shortDate() -> String {
        Date.now.formatted(date: .numeric, time: .shortened)
    }
}

struct AttachmentSelection: Identifiable {
    let id = UUID()
    let attachment: Attachment
}
