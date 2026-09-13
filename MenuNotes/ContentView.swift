import SwiftUI
import AppKit
import Combine

// MARK: - Quản lý Editor theo Environment Context

final class EditorContext: ObservableObject {
    weak var textView: NSTextView?
}

// MARK: - Content View

struct ContentView: View {

    @StateObject private var store = NoteStore()
    @StateObject private var editorContext = EditorContext()

    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: Tabs
            TabBarView(store: store)
            Divider()

            // MARK: Toolbar
            FormatToolbar()
                .environmentObject(editorContext)
            Divider()

            // MARK: Editor
            if let note = store.selectedNote {
                RichTextEditor(
                    text: Binding(
                        get: { note.attributedContent },
                        set: { newContent in store.updateContent(note.id, content: newContent) }
                    )
                )
                .environmentObject(editorContext)
                .id(note.id)
            } else {
                Text("Không có note nào")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 480, height: 420)
    }
}

// MARK: - Format Toolbar

struct FormatToolbar: View {
    
    @EnvironmentObject var editorContext: EditorContext
    
    @State private var currentTextStyle: TextStyle = .body
    @State private var isColorPopoverPresented = false
    @State private var selectedColor: NSColor?

    let presetColors: [NSColor] = [
        .systemPurple, .systemPink, .systemOrange, .systemMint, .systemBlue
    ]

    var body: some View {
        HStack(spacing: 6) {

            // MARK: Bold / Italic / Underline
            FormatButton(symbol: "bold") { applyTrait(.boldFontMask) }
            FormatButton(symbol: "italic") { applyTrait(.italicFontMask) }
            FormatButton(symbol: "underline") { toggleUnderline() }

            Divider().frame(height: 16)

            // MARK: Text Color
            Button {
                isColorPopoverPresented.toggle()
            } label: {
                Image(systemName: "paintpalette").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .popover(isPresented: $isColorPopoverPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        selectedColor = nil
                        applyColor(nil)
                        isColorPopoverPresented = false
                    } label: {
                        Text("Reset (màu hệ thống)")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedColor == nil ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    HStack(spacing: 8) {
                        ForEach(presetColors, id: \.self) { color in
                            Button {
                                selectedColor = color
                                applyColor(color)
                                isColorPopoverPresented = false
                            } label: {
                                Circle()
                                    .fill(Color(color))
                                    .frame(width: 18, height: 18)
                                    .padding(4)
                                    .background(selectedColor == color ? Color(color).opacity(0.3) : Color.clear)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(8)
            }

            // MARK: Text Style
            Menu {
                ForEach(TextStyle.allCases, id: \.self) { style in
                    Button {
                        currentTextStyle = style
                        applyTextStyle(style)
                    } label: {
                        HStack {
                            if currentTextStyle == style { Image(systemName: "checkmark") }
                            Text(style.rawValue)
                                .font(.system(size: style.size, weight: style.isBold ? .bold : .regular))
                        }
                    }
                }
            } label: {
                Image(systemName: "textformat.size").font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)

            Divider().frame(height: 16)

            // MARK: Checklist
            FormatButton(symbol: "checklist") { insertChecklist() }

            Spacer()

            // MARK: Undo / Redo
            FormatButton(symbol: "arrow.uturn.backward") { undo() }
            FormatButton(symbol: "arrow.uturn.forward") { redo() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func currentTextView() -> NSTextView? { editorContext.textView }

    private func applyTrait(_ trait: NSFontTraitMask) {
        currentTextView()?.changeFontTrait(trait)
    }

    private func toggleUnderline() {
        guard let tv = currentTextView() else { return }
        let range = tv.selectedRange()
        let attrs = tv.typingAttributes
        let current = (attrs[.underlineStyle] as? Int) ?? 0
        let newValue = current == 0 ? NSUnderlineStyle.single.rawValue : 0

        if range.length > 0 {
            tv.textStorage?.addAttribute(.underlineStyle, value: newValue, range: range)
        }
        var typing = tv.typingAttributes
        typing[.underlineStyle] = newValue
        tv.typingAttributes = typing
        tv.notifyTextDidChange()
    }

    private func applyColor(_ color: NSColor?) {
        guard let tv = currentTextView() else { return }
        let range = tv.selectedRange()
        let finalColor = color ?? NSColor.labelColor

        if range.length > 0 {
            tv.textStorage?.addAttribute(.foregroundColor, value: finalColor, range: range)
        }
        var typing = tv.typingAttributes
        typing[.foregroundColor] = finalColor
        tv.typingAttributes = typing
        tv.notifyTextDidChange()
    }

    private func applyTextStyle(_ style: TextStyle) {
        guard let tv = currentTextView() else { return }
        let range = tv.selectedRange()
        let manager = NSFontManager.shared

        if range.length > 0 {
            tv.textStorage?.enumerateAttribute(.font, in: range) { value, subRange, _ in
                guard let font = value as? NSFont else { return }
                var newFont = manager.convert(font, toSize: style.size)
                newFont = manager.convert(newFont, toHaveTrait: style.isBold ? .boldFontMask : .unboldFontMask)
                tv.textStorage?.addAttribute(.font, value: newFont, range: subRange)
            }
        }

        var typing = tv.typingAttributes
        if let font = typing[.font] as? NSFont {
            var newFont = manager.convert(font, toSize: style.size)
            newFont = manager.convert(newFont, toHaveTrait: style.isBold ? .boldFontMask : .unboldFontMask)
            typing[.font] = newFont
        } else {
            var newFont = NSFont.systemFont(ofSize: style.size)
            if style.isBold { newFont = manager.convert(newFont, toHaveTrait: .boldFontMask) }
            typing[.font] = newFont
        }
        tv.typingAttributes = typing
        tv.notifyTextDidChange()
    }

    private func insertChecklist() {
        guard let tv = currentTextView() else { return }
        let string = tv.string as NSString
        let range = tv.selectedRange()
        
        // Xác định toàn bộ dòng hiện tại
        let paraRange = string.paragraphRange(for: range)
        let paraString = string.substring(with: paraRange)
        
        tv.undoManager?.beginUndoGrouping()
        
        // Nếu dòng hiện hành đã là checklist -> Xóa định dạng checklist
        if paraString.hasPrefix("☐ ") || paraString.hasPrefix("☑ ") {
            tv.insertText("", replacementRange: NSRange(location: paraRange.location, length: 2))
            
            let resetStyle = NSMutableParagraphStyle()
            let newParaRange = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
            tv.textStorage?.addAttribute(.paragraphStyle, value: resetStyle, range: newParaRange)
            tv.typingAttributes[.paragraphStyle] = resetStyle
            
        } else {
            // Nếu là dòng thường -> Biến thành checklist
            let checklist = NSMutableAttributedString(string: "☐ ")
            checklist.addAttribute(.link, value: "checklist://toggle", range: NSRange(location: 0, length: 1))
            checklist.addAttribute(.font, value: NSFont.systemFont(ofSize: 16), range: NSRange(location: 0, length: 1))
            checklist.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: 1))

            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = 24
            paragraph.firstLineHeadIndent = 0
            
            tv.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: paraRange)
            tv.insertText(checklist, replacementRange: NSRange(location: paraRange.location, length: 0))
            tv.typingAttributes[.paragraphStyle] = paragraph
        }
        
        tv.undoManager?.endUndoGrouping()
    }

    private func undo() { currentTextView()?.undoManager?.undo() }
    private func redo() { currentTextView()?.undoManager?.redo() }
}

// MARK: - Format Button

struct FormatButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .cornerRadius(4)
    }
}

// MARK: - NSTextView Font Helper

extension NSTextView {
    func changeFontTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange()
        let manager = NSFontManager.shared

        if range.length > 0 {
            textStorage?.enumerateAttribute(.font, in: range) { value, subRange, _ in
                guard let font = value as? NSFont else { return }
                let newFont = manager.convert(font, toHaveTrait: trait)
                textStorage?.addAttribute(.font, value: newFont, range: subRange)
            }
        }
        var typing = typingAttributes
        if let font = typing[.font] as? NSFont {
            typing[.font] = manager.convert(font, toHaveTrait: trait)
        } else {
            typing[.font] = manager.convert(NSFont.systemFont(ofSize: 14), toHaveTrait: trait)
        }
        typingAttributes = typing
        notifyTextDidChange()
    }

    func notifyTextDidChange() {
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: self)
    }
}

// MARK: - Tab Bar

struct TabBarView: View {
    @ObservedObject var store: NoteStore
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var now = Date()

    private let relativeTimeTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.notes) { note in tabItem(for: note) }
                Button { store.addNote() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .menuNotesDidShow)) { _ in now = Date() }
        .onReceive(relativeTimeTimer) { date in now = date }
    }

    @ViewBuilder private func tabItem(for note: Note) -> some View {
        TabItemView(
            note: note,
            isSelected: store.selectedNoteID == note.id,
            isRenaming: renamingID == note.id,
            renameText: $renameText,
            now: now,
            onSelect: { store.selectNote(note) },
            onRenameStart: {
                renamingID = note.id
                renameText = note.title
            },
            onRenameCommit: {
                let newTitle = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                store.renameNote(note, newTitle: newTitle.isEmpty ? "Note" : newTitle)
                renamingID = nil
            },
            onRenameCancel: { renamingID = nil },
            onDelete: { store.deleteNote(note) },
            canDelete: store.notes.count > 1
        )
    }
}

// MARK: - Tab Item

struct TabItemView: View {
    let note: Note
    let isSelected: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    let now: Date
    let onSelect: () -> Void
    let onRenameStart: () -> Void
    let onRenameCommit: () -> Void
    let onRenameCancel: () -> Void
    let onDelete: () -> Void
    let canDelete: Bool

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "vi_VN")
        return formatter
    }()

    private var relativeTime: String {
        let interval = now.timeIntervalSince(note.lastModified)
        if interval < 60 { return "vừa mới cập nhật" }
        return Self.relativeFormatter.localizedString(for: note.lastModified, relativeTo: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if isRenaming {
                    TextField("", text: $renameText, onCommit: onRenameCommit)
                        .textFieldStyle(.plain)
                        .frame(width: 90)
                        .onExitCommand { onRenameCancel() }
                } else {
                    Text(note.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(relativeTime)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                if canDelete && !isRenaming {
                    Button(action: onDelete) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .opacity(0.5)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(minWidth: 110)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .cornerRadius(6)
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1) }
        .contentShape(Rectangle())
        .onTapGesture { if !isRenaming { onSelect() } }
        .contextMenu {
            Button("Đổi tên…") { onRenameStart() }
            if canDelete {
                Divider()
                Button("Xóa", role: .destructive) { onDelete() }
            }
        }
    }
}

// MARK: - Rich Text Editor

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    @EnvironmentObject var editorContext: EditorContext

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.usesInspectorBar = false
        
        textView.linkTextAttributes = [:]

        DispatchQueue.main.async {
            editorContext.textView = textView
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let currentText = textView.attributedString()
        guard currentText != text else { return }

        let currentRange = textView.selectedRange()
        textView.textStorage?.setAttributedString(text)

        let safeLocation = min(currentRange.location, text.length)
        let safeLength = min(currentRange.length, max(0, text.length - safeLocation))
        textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let textView = nsView.documentView as? NSTextView {
            textView.delegate = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.attributedString()
            guard parent.text != newText else { return }
            parent.text = newText
        }

        // Đánh chặn phím (Enter, Xóa, ...)
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            
            // Xử lý riêng khi ấn phím Enter (Return)
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let range = textView.selectedRange()
                let string = textView.string as NSString
                let paraRange = string.paragraphRange(for: range)
                let paraString = string.substring(with: paraRange)
                
                // Kiểm tra xem dòng hiện hành có phải là Checklist không
                if paraString.hasPrefix("☐ ") || paraString.hasPrefix("☑ ") {
                    
                    // Cắt bỏ ô checkbox và khoảng trắng để xem người dùng đã gõ chữ gì chưa
                    let trimmed = paraString.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if trimmed.isEmpty {
                        // Trạng thái 1: Nhấn Enter trên một Checklist rỗng -> Hủy Checklist
                        textView.undoManager?.beginUndoGrouping()
                        
                        // Xóa biểu tượng checkbox hiện tại
                        textView.insertText("", replacementRange: NSRange(location: paraRange.location, length: 2))
                        
                        // Đặt lại lề về 0 (chuẩn)
                        let resetStyle = NSMutableParagraphStyle()
                        let newParaRange = (textView.string as NSString).paragraphRange(for: textView.selectedRange())
                        textView.textStorage?.addAttribute(.paragraphStyle, value: resetStyle, range: newParaRange)
                        textView.typingAttributes[.paragraphStyle] = resetStyle
                        
                        textView.undoManager?.endUndoGrouping()
                        return true
                        
                    } else {
                        // Trạng thái 2: Nhấn Enter trên Checklist đang có chữ -> Sinh ra Checklist mới ở dòng tiếp theo
                        textView.undoManager?.beginUndoGrouping()
                        
                        // Sinh dòng mới
                        textView.insertText("\n", replacementRange: range)
                        
                        // Chèn checkbox mới
                        let checklist = NSMutableAttributedString(string: "☐ ")
                        checklist.addAttribute(.link, value: "checklist://toggle", range: NSRange(location: 0, length: 1))
                        checklist.addAttribute(.font, value: NSFont.systemFont(ofSize: 16), range: NSRange(location: 0, length: 1))
                        checklist.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: 1))
                        
                        // Căn lề thụt đầu dòng
                        let paragraph = NSMutableParagraphStyle()
                        paragraph.headIndent = 24
                        paragraph.firstLineHeadIndent = 0
                        checklist.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: checklist.length))
                        
                        textView.insertText(checklist, replacementRange: textView.selectedRange())
                        textView.typingAttributes[.paragraphStyle] = paragraph
                        
                        textView.undoManager?.endUndoGrouping()
                        return true
                    }
                }
            }
            return false
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let urlString = link as? String, urlString == "checklist://toggle" {
                toggleChecklist(at: charIndex, in: textView)
                return true
            }
            return false
        }
        
        // Đăng ký lịch sử Undo/Redo cho thao tác Tick hộp kiểm
        @objc func toggleChecklist(at charIndex: Int, in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let char = (textStorage.string as NSString).substring(with: NSRange(location: charIndex, length: 1))
            let replacement = char == "☐" ? "☑" : "☐"
            
            textView.undoManager?.registerUndo(withTarget: self, handler: { target in
                target.toggleChecklist(at: charIndex, in: textView)
            })
            
            textStorage.replaceCharacters(in: NSRange(location: charIndex, length: 1), with: replacement)
            textView.notifyTextDidChange()
        }
    }
}

// MARK: - Text Style

enum TextStyle: String, CaseIterable {
    case title = "Title"
    case heading = "Heading"
    case subheading = "Subheading"
    case body = "Body"
    case subbody = "Subbody"

    var size: CGFloat {
        switch self {
        case .title: return 24
        case .heading: return 20
        case .subheading: return 16
        case .body: return 14
        case .subbody: return 12
        }
    }

    var isBold: Bool {
        switch self {
        case .title, .heading, .subheading: return true
        case .body, .subbody: return false
        }
    }
}
