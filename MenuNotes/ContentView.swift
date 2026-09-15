import SwiftUI
import AppKit
import Combine

// MARK: - Checklist Helper

enum ChecklistUI {
    static let attributeKey = NSAttributedString.Key("isChecklist")
    
    static func icon(isChecked: Bool, font: NSFont = .systemFont(ofSize: 14), color: NSColor = .labelColor) -> NSAttributedString {
        let symbolName = isChecked ? "checkmark.circle.fill" : "circle"
        
        let config: NSImage.SymbolConfiguration
        if isChecked {
            config = NSImage.SymbolConfiguration(pointSize: font.pointSize + 1, weight: .medium)
                .applying(.init(paletteColors: [
                    NSColor.black,
                    NSColor(red: 255/255, green: 204/255, blue: 0/255, alpha: 1)
                ]))
        } else {
            config = NSImage.SymbolConfiguration(pointSize: font.pointSize + 1, weight: .regular)
                .applying(.init(paletteColors: [NSColor.tertiaryLabelColor]))
        }
        
        let attachment = NSTextAttachment()
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            attachment.image = image
            let size = font.pointSize + 3
            let yOffset = -((font.pointSize - 14) / 2) - 2.5
            attachment.bounds = NSRect(x: 0, y: yOffset, width: size, height: size)
        }
        
        let attrString = NSMutableAttributedString(attachment: attachment)
        let fullRange = NSRange(location: 0, length: attrString.length)
        
        attrString.addAttribute(.font, value: font, range: fullRange)
        attrString.addAttribute(.foregroundColor, value: color, range: fullRange)
        attrString.addAttribute(.link, value: "checklist://toggle", range: fullRange)
        attrString.addAttribute(attributeKey, value: isChecked, range: fullRange)
        
        return attrString
    }
}

// MARK: - Quản lý Editor theo Environment Context

final class EditorContext: ObservableObject {
    weak var textView: NSTextView?
    
    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderline: Bool = false
    @Published var currentColor: NSColor? = nil
    @Published var currentTextStyle: TextStyle = .body
    
    func syncState() {
        guard let tv = textView else { return }
        let attrs = tv.typingAttributes
        
        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            isBold = traits.contains(.bold)
            isItalic = traits.contains(.italic)
            
            let size = font.pointSize
            currentTextStyle = TextStyle.allCases.min(by: { abs($0.size - size) < abs($1.size - size) }) ?? .body
        } else {
            isBold = false
            isItalic = false
            currentTextStyle = .body
        }
        
        if let underline = attrs[.underlineStyle] as? Int, underline != 0 {
            isUnderline = true
        } else {
            isUnderline = false
        }
        
        if let color = attrs[.foregroundColor] as? NSColor {
            if color.isEqual(to: NSColor.labelColor) || color.isEqual(to: NSColor.textColor) {
                currentColor = nil
            } else {
                currentColor = color
            }
        } else {
            currentColor = nil
        }
    }
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
    @State private var isColorPopoverPresented = false

    let presetColors: [(color: NSColor?, title: String)] = [
        (nil, "Mặc định (Trắng/Đen)"),
        (.systemPurple, "Purple"),
        (.systemPink, "Pink"),
        (.systemOrange, "Orange"),
        (.systemMint, "Mint"),
        (.systemBlue, "Blue")
    ]

    var body: some View {
        HStack(spacing: 6) {

            // MARK: Bold / Italic / Underline
            FormatButton(symbol: "bold", isActive: editorContext.isBold) {
                applyTrait(editorContext.isBold ? .unboldFontMask : .boldFontMask)
            }
            FormatButton(symbol: "italic", isActive: editorContext.isItalic) {
                applyTrait(editorContext.isItalic ? .unitalicFontMask : .italicFontMask)
            }
            FormatButton(symbol: "underline", isActive: editorContext.isUnderline) { toggleUnderline() }

            Divider().frame(height: 16)

            // MARK: Text Color
            Button {
                isColorPopoverPresented.toggle()
            } label: {
                Image(systemName: "circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(editorContext.currentColor != nil ? Color(editorContext.currentColor!) : .primary)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 24)
            .popover(isPresented: $isColorPopoverPresented, arrowEdge: .bottom) {
                HStack(spacing: 8) {
                    ForEach(0..<presetColors.count, id: \.self) { index in
                        let item = presetColors[index]
                        Button {
                            applyColor(item.color)
                            isColorPopoverPresented = false
                        } label: {
                            Circle()
                                .fill(item.color != nil ? Color(item.color!) : Color.white)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.5), lineWidth: item.color == nil ? 1 : 0)
                                )
                                .frame(width: 18, height: 18)
                                .padding(4)
                                .background(
                                    (item.color == nil && editorContext.currentColor == nil) ||
                                    (item.color != nil && editorContext.currentColor != nil && item.color!.isApproximatelyEqual(to: editorContext.currentColor))
                                    ? Color.accentColor.opacity(0.3)
                                    : Color.clear
                                )
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help(item.title)
                    }
                }
                .padding(8)
            }

            // MARK: Text Style Dropdown
            Menu {
                ForEach(TextStyle.allCases, id: \.self) { style in
                    Button {
                        applyTextStyle(style)
                    } label: {
                        HStack {
                            if editorContext.currentTextStyle == style { Image(systemName: "checkmark") }
                            Text("\(style.rawValue) (\(Int(style.size))pt)")
                                .font(.system(size: style.size, weight: style.isBold ? .bold : .regular))
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text("\(editorContext.currentTextStyle.rawValue) \(Int(editorContext.currentTextStyle.size))")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 4)
                .frame(height: 24)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)

            Divider().frame(height: 16)

            // MARK: Checklist
            FormatButton(symbol: "checklist") { insertChecklist() }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func currentTextView() -> NSTextView? { editorContext.textView }

    private func applyTrait(_ trait: NSFontTraitMask) {
        currentTextView()?.changeFontTrait(trait)
        editorContext.syncState()
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
        editorContext.syncState()
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
        editorContext.syncState()
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
        editorContext.syncState()
    }

    private func insertChecklist() {
        guard let tv = currentTextView(), let textStorage = tv.textStorage else { return }
        let string = tv.string as NSString
        let range = tv.selectedRange()
        let paraRange = string.paragraphRange(for: range)
        
        // Bounds safety
        guard paraRange.location <= textStorage.length else { return }
        
        let typingAttrs = tv.typingAttributes
        let currentFont = (typingAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14)
        let currentColor = (typingAttrs[.foregroundColor] as? NSColor) ?? NSColor.labelColor
        
        var hasChecklist = false
        if paraRange.location < textStorage.length {
            hasChecklist = textStorage.attribute(ChecklistUI.attributeKey, at: paraRange.location, effectiveRange: nil) != nil
        }
        
        tv.undoManager?.beginUndoGrouping()
        
        if hasChecklist {
            // Chỉ xóa khi đủ 2 ký tự (icon + space)
            let deleteLength = min(2, textStorage.length - paraRange.location)
            guard deleteLength > 0 else {
                tv.undoManager?.endUndoGrouping()
                return
            }
            let deleteRange = NSRange(location: paraRange.location, length: deleteLength)
            textStorage.replaceCharacters(in: deleteRange, with: "")
            
            let resetStyle = NSMutableParagraphStyle()
            let newParaRange = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
            if newParaRange.location + newParaRange.length <= textStorage.length {
                textStorage.addAttribute(.paragraphStyle, value: resetStyle, range: newParaRange)
            }
            tv.typingAttributes[.paragraphStyle] = resetStyle
        } else {
            let checklist = NSMutableAttributedString()
            checklist.append(ChecklistUI.icon(isChecked: false, font: currentFont, color: currentColor))
            checklist.append(NSAttributedString(string: " ", attributes: [.font: currentFont, .foregroundColor: currentColor]))
            
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = 24
            paragraph.firstLineHeadIndent = 0
            checklist.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: checklist.length))
            
            // Insert an toàn
            let insertLoc = min(paraRange.location, textStorage.length)
            textStorage.insert(checklist, at: insertLoc)
            
            let newParaRange = (tv.string as NSString).paragraphRange(for: NSRange(location: insertLoc, length: checklist.length))
            if newParaRange.location + newParaRange.length <= textStorage.length {
                textStorage.addAttribute(.paragraphStyle, value: paragraph, range: newParaRange)
            }
            tv.typingAttributes[.paragraphStyle] = paragraph
        }
        
        tv.undoManager?.endUndoGrouping()
        tv.notifyTextDidChange()
        editorContext.syncState()
    }
}

// MARK: - Format Button

struct FormatButton: View {
    let symbol: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
    }
}

// MARK: - NSTextView Extension

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
                    .focusable(false)
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
        
        let textView = NSTextView() // Sử dụng class chuẩn của macOS
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.usesInspectorBar = false
        
        textView.linkTextAttributes = [:]

        textView.backgroundColor = NSColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)
        textView.drawsBackground = true

        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(red: 150/255, green: 112/255, blue: 84/255, alpha: 0.55)
        ]
        
        DispatchQueue.main.async {
            editorContext.textView = textView
            editorContext.syncState()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard !context.coordinator.isEditing else { return }
        guard let textView = nsView.documentView as? NSTextView else { return }
        let currentText = textView.attributedString()
        
        guard !currentText.isEqual(to: text) else { return }

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
        var isEditing = false

        init(_ parent: RichTextEditor) { self.parent = parent }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let textView = notification.object as? NSTextView,
               let textStorage = textView.textStorage {
                let range = textView.selectedRange()
                
                // Xóa highlight nếu vô tình bôi đen đúng 1 ký tự checklist
                if range.length == 1 {
                    let isChecklist = textStorage.attribute(ChecklistUI.attributeKey, at: range.location, effectiveRange: nil) != nil
                    if isChecklist {
                        let safeLocation = min(range.location + 1, textStorage.length)
                        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.parent.editorContext.syncState()
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            let newText = textView.attributedString()
            if !parent.text.isEqual(to: newText) {
                parent.text = newText
            }
            isEditing = false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let range = textView.selectedRange()
                let string = textView.string as NSString
                let paraRange = string.paragraphRange(for: range)
                
                guard let textStorage = textView.textStorage,
                      paraRange.length > 0,
                      paraRange.location < textStorage.length else { return false }
                
                let hasChecklist = textStorage.attribute(ChecklistUI.attributeKey, at: paraRange.location, effectiveRange: nil) != nil
                
                if hasChecklist {
                    let paraString = string.substring(with: paraRange)
                    let trimmed = paraString.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    if trimmed.isEmpty {
                        textView.undoManager?.beginUndoGrouping()
                        let deleteLength = min(2, textStorage.length - paraRange.location)
                        guard deleteLength > 0 else {
                            textView.undoManager?.endUndoGrouping()
                            return true
                        }
                        let deleteRange = NSRange(location: paraRange.location, length: deleteLength)
                        textStorage.replaceCharacters(in: deleteRange, with: "")
                        
                        let resetStyle = NSMutableParagraphStyle()
                        let newParaRange = (textView.string as NSString).paragraphRange(for: textView.selectedRange())
                        if newParaRange.location + newParaRange.length <= textStorage.length {
                            textStorage.addAttribute(.paragraphStyle, value: resetStyle, range: newParaRange)
                        }
                        textView.typingAttributes[.paragraphStyle] = resetStyle
                        
                        textView.undoManager?.endUndoGrouping()
                        textView.notifyTextDidChange()
                        return true
                        
                    } else {
                        textView.undoManager?.beginUndoGrouping()
                        
                        let typingAttrs = textView.typingAttributes
                        let currentFont = (typingAttrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14)
                        let currentColor = (typingAttrs[.foregroundColor] as? NSColor) ?? NSColor.labelColor
                        
                        textStorage.replaceCharacters(in: range, with: "\n")
                        
                        let checklist = NSMutableAttributedString()
                        checklist.append(ChecklistUI.icon(isChecked: false, font: currentFont, color: currentColor))
                        checklist.append(NSAttributedString(string: " ", attributes: [
                            .font: currentFont,
                            .foregroundColor: currentColor
                        ]))
                        
                        let paragraph = NSMutableParagraphStyle()
                        paragraph.headIndent = 24
                        paragraph.firstLineHeadIndent = 0
                        checklist.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: checklist.length))
                        
                        let insertLoc = min(range.location + 1, textStorage.length)
                        textStorage.insert(checklist, at: insertLoc)
                        
                        textView.setSelectedRange(NSRange(location: insertLoc + checklist.length, length: 0))
                        
                        var newTyping = typingAttrs
                        newTyping[.paragraphStyle] = paragraph
                        newTyping[.font] = currentFont
                        newTyping[.foregroundColor] = currentColor
                        textView.typingAttributes = newTyping
                        
                        textView.undoManager?.endUndoGrouping()
                        textView.notifyTextDidChange()
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
        
        @objc func toggleChecklist(at charIndex: Int, in textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  charIndex >= 0,
                  charIndex < textStorage.length else { return }
            
            let isChecked = textStorage.attribute(ChecklistUI.attributeKey, at: charIndex, effectiveRange: nil) as? Bool ?? false
            let currentFont = (textStorage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let currentColor = (textStorage.attribute(.foregroundColor, at: charIndex, effectiveRange: nil) as? NSColor) ?? NSColor.labelColor
            
            let newIcon = ChecklistUI.icon(isChecked: !isChecked, font: currentFont, color: currentColor)
            
            textView.undoManager?.registerUndo(withTarget: self, handler: { target in
                target.toggleChecklist(at: charIndex, in: textView)
            })
            
            textStorage.replaceCharacters(in: NSRange(location: charIndex, length: 1), with: newIcon)
            
            // THÊM DÒNG NÀY: Bỏ trạng thái select sau khi tick
            textView.setSelectedRange(NSRange(location: min(charIndex + 1, textStorage.length), length: 0))
            
            textView.notifyTextDidChange()
        }
        
        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            guard let textStorage = view.textStorage, charIndex >= 0, charIndex < textStorage.length else { return menu }
            
            let isChecklist = textStorage.attribute(ChecklistUI.attributeKey, at: charIndex, effectiveRange: nil) != nil
            if isChecklist {
                return nil // Chặn trình đơn Markup/AutoFill
            }
            
            return menu
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

// MARK: - NSColor Extension
extension NSColor {
    func isApproximatelyEqual(to other: NSColor?) -> Bool {
        guard let other = other else { return false }
        guard let c1 = usingColorSpace(.sRGB), let c2 = other.usingColorSpace(.sRGB) else {
            return self == other
        }
        return abs(c1.redComponent - c2.redComponent) < 0.01 &&
               abs(c1.greenComponent - c2.greenComponent) < 0.01 &&
               abs(c1.blueComponent - c2.blueComponent) < 0.01 &&
               abs(c1.alphaComponent - c2.alphaComponent) < 0.01
    }
}
