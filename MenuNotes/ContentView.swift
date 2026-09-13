import SwiftUI
import AppKit

// MARK: - Quản lý Active Editor (Tránh đệ quy UI)
class ActiveEditor {
    static weak var textView: NSTextView?
}

struct ContentView: View {
    @StateObject private var store = NoteStore()
    
    var body: some View {
        VStack(spacing: 0) {
            TabBarView(store: store)
            
            Divider()
            
            // Toolbar định dạng
            FormatToolbar()
            
            Divider()
            
            if let note = store.selectedNote {
                RichTextEditor(text: Binding(
                    get: { note.attributedContent },
                    set: { store.updateContent(note.id, content: $0) }
                ))
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
    @State private var currentTextStyle: TextStyle = .body
    @State private var isColorPopoverPresented = false
    @State private var selectedColor: NSColor? = nil

    let presetColors: [NSColor] = [
        .systemPurple,
        .systemPink,
        .systemOrange,
        .systemMint,
        .systemBlue
    ]
    
    var body: some View {
        HStack(spacing: 6) {
            // Bold / Italic / Underline
            FormatButton(symbol: "bold", action: { applyTrait(.boldFontMask) })
            FormatButton(symbol: "italic", action: { applyTrait(.italicFontMask) })
            FormatButton(symbol: "underline", action: { toggleUnderline() })
            
            Divider().frame(height: 16)
            
            // Text Color
            Button(action: { isColorPopoverPresented.toggle() }) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .popover(isPresented: $isColorPopoverPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    // Nút Reset
                    Button(action: {
                        selectedColor = nil
                        applyColor(nil)
                        isColorPopoverPresented = false
                    }) {
                        Text("Reset (màu hệ thống)")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedColor == nil ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                    
                    // Bảng màu
                    HStack(spacing: 8) {
                        ForEach(presetColors, id: \.self) { color in
                            Button(action: {
                                selectedColor = color
                                applyColor(color)
                                isColorPopoverPresented = false
                            }) {
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
            
            // Font Size / Text Style
            Menu {
                ForEach(TextStyle.allCases, id: \.self) { style in
                    Button {
                        currentTextStyle = style
                        applyTextStyle(style)
                    } label: {
                        HStack {
                            if currentTextStyle == style {
                                Image(systemName: "checkmark")
                            }
                            Text(style.rawValue)
                                .font(.system(size: style.size, weight: style.isBold ? .bold : .regular))
                        }
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            
            Divider().frame(height: 16)
            
            // Checklist
            FormatButton(symbol: "checklist", action: { insertChecklist() })
            
            Spacer()
            
            // Undo / Redo
            FormatButton(symbol: "arrow.uturn.backward", action: { undo() })
            FormatButton(symbol: "arrow.uturn.forward", action: { redo() })
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Actions
    private func currentTextView() -> NSTextView? {
        return ActiveEditor.textView
    }
    
    private func applyTrait(_ trait: NSFontTraitMask) {
        guard let tv = currentTextView() else { return }
        tv.changeFontTrait(trait)
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
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: tv)
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
        
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: tv)
    }
    
    private func applyTextStyle(_ style: TextStyle) {
        guard let tv = currentTextView() else { return }
        let range = tv.selectedRange()
        let manager = NSFontManager.shared
        
        if range.length > 0 {
            tv.textStorage?.enumerateAttribute(.font, in: range) { value, subRange, _ in
                if let font = value as? NSFont {
                    var newFont = manager.convert(font, toSize: style.size)
                    if style.isBold {
                        newFont = manager.convert(newFont, toHaveTrait: .boldFontMask)
                    } else {
                        newFont = manager.convert(newFont, toNotHaveTrait: .boldFontMask)
                    }
                    tv.textStorage?.addAttribute(.font, value: newFont, range: subRange)
                }
            }
        }
        
        var typing = tv.typingAttributes
        if let font = typing[.font] as? NSFont {
            var newFont = manager.convert(font, toSize: style.size)
            if style.isBold {
                newFont = manager.convert(newFont, toHaveTrait: .boldFontMask)
            } else {
                newFont = manager.convert(newFont, toNotHaveTrait: .boldFontMask)
            }
            typing[.font] = newFont
        } else {
            var newFont = NSFont.systemFont(ofSize: style.size)
            if style.isBold {
                newFont = manager.convert(newFont, toHaveTrait: .boldFontMask)
            }
            typing[.font] = newFont
        }
        
        tv.typingAttributes = typing
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: tv)
    }
    
    private func insertChecklist() {
        guard let tv = currentTextView() else { return }
        
        let checklist = NSMutableAttributedString(string: "☐  ")
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 18
        paragraph.firstLineHeadIndent = 0
        checklist.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: checklist.length))
        
        let range = tv.selectedRange()
        tv.insertText(checklist, replacementRange: range)
        tv.setSelectedRange(NSRange(location: range.location + checklist.length, length: 0))
    }
    
    private func undo() {
        currentTextView()?.undoManager?.undo()
    }
    
    private func redo() {
        currentTextView()?.undoManager?.redo()
    }
}

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

// MARK: - Helper extension cho Bold / Italic
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
        
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: self)
    }
}

// MARK: - Tab Bar
struct TabBarView: View {
    @ObservedObject var store: NoteStore
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @State private var now = Date()
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.notes) { note in
                    tabItem(for: note)
                }
                
                Button(action: { store.addNote() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .menuNotesDidShow)) { _ in
            now = Date()
        }
    }
    
    @ViewBuilder
    private func tabItem(for note: Note) -> some View {
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
            onRenameCancel: {
                renamingID = nil
            },
            onDelete: { store.deleteNote(note) },
            canDelete: store.notes.count > 1
        )
    }
}

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
    
    private var relativeTime: String {
        let interval = now.timeIntervalSince(note.lastModified)
        if interval < 60 { return "vừa mới cập nhật" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "vi_VN")
        return formatter.localizedString(for: note.lastModified, relativeTo: now)
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
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .opacity(0.5)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 110)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isRenaming { onSelect() }
        }
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
        
        // Lưu trữ tham chiếu trực tiếp để tránh đệ quy
        ActiveEditor.textView = textView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.attributedString() != text {
            let currentRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(text)
            
            let safeLocation = min(currentRange.location, text.length)
            let safeLength = min(currentRange.length, text.length - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        
        init(_ parent: RichTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.attributedString()
        }
    }
}

// MARK: - Text Style Enum
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
