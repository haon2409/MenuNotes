import Foundation
import AppKit
import Combine

// MARK: - Note Model

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var contentData: Data
    var lastModified: Date

    var attributedContent: NSAttributedString {
        get {
            (try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSAttributedString.self,
                from: contentData
            )) ?? NSAttributedString(string: "")
        }
        set {
            contentData = (try? NSKeyedArchiver.archivedData(
                withRootObject: newValue,
                requiringSecureCoding: false
            )) ?? Data()
        }
    }

    init(
        title: String = "Note mới",
        content: NSAttributedString = NSAttributedString(string: "")
    ) {
        self.title = title
        self.contentData = (try? NSKeyedArchiver.archivedData(
            withRootObject: content,
            requiringSecureCoding: false
        )) ?? Data()
        self.lastModified = Date()
    }
}

// MARK: - Note Store

@MainActor
final class NoteStore: ObservableObject {

    @Published private(set) var notes: [Note] = []
    @Published var selectedNoteID: UUID?

    private let contentSaveDelay: UInt64 = 400_000_000
    private var pendingSaveTask: Task<Void, Never>?
    private var terminationObserver: NSObjectProtocol?
    
    // Tạo đường dẫn lưu file an toàn
    private var storeURL: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = urls[0].appendingPathComponent("MenuNotes")
        
        if !FileManager.default.fileExists(atPath: appSupportURL.path) {
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        }
        
        return appSupportURL.appendingPathComponent("notes_data.json")
    }

    init() {
        load()

        if notes.isEmpty {
            let first = Note(title: "Note 1")
            notes.append(first)
            selectedNoteID = first.id
            saveImmediately()
        } else {
            selectedNoteID = notes.max(
                by: { $0.lastModified < $1.lastModified }
            )?.id
        }

        setupTerminationObserver()
    }

    deinit {
        pendingSaveTask?.cancel()
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    func addNote() {
        let newNote = Note(title: nextNoteTitle())
        notes.append(newNote)
        selectedNoteID = newNote.id
        saveImmediately()
    }

    func deleteNote(_ note: Note) {
        guard notes.count > 1 else { return }
        flushPendingSave()
        notes.removeAll { $0.id == note.id }
        if selectedNoteID == note.id {
            selectedNoteID = notes.last?.id
        }
        saveImmediately()
    }

    func renameNote(_ note: Note, newTitle: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.isEmpty ? "Note" : trimmedTitle
        guard notes[index].title != finalTitle else { return }
        
        notes[index].title = finalTitle
        notes[index].lastModified = Date()
        saveImmediately()
    }

    func updateContent(_ noteID: UUID, content: NSAttributedString) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let oldContent = notes[index].attributedContent
        guard oldContent != content else { return }
        
        notes[index].attributedContent = content
        notes[index].lastModified = Date()
        scheduleContentSave()
    }

    func selectNote(_ note: Note) {
        guard selectedNoteID != note.id else { return }
        selectedNoteID = note.id
    }

    private func scheduleContentSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.contentSaveDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.saveImmediately()
            self.pendingSaveTask = nil
        }
    }

    func flushPendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        saveImmediately()
    }

    private func saveImmediately() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        // Lưu ra File System thay vì UserDefaults
        try? data.write(to: storeURL, options: .atomic)
    }

    private func load() {
        // Đọc từ File System
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else {
            return
        }
        notes = decoded
    }

    private func nextNoteTitle() -> String {
        // Lấy danh sách các số từ chuỗi "Note X" và tìm số Max
        let numbers = notes.compactMap { note -> Int? in
            let prefix = "Note "
            guard note.title.hasPrefix(prefix),
                  let numString = note.title.components(separatedBy: prefix).last,
                  let number = Int(numString) else {
                return nil
            }
            return number
        }
        let maxNumber = numbers.max() ?? 0
        return "Note \(maxNumber + 1)"
    }

    private func setupTerminationObserver() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flushPendingSave()
        }
    }
}
