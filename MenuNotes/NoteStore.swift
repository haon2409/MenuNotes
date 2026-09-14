import Foundation
import AppKit
import Combine

// MARK: - Note Model

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var lastModified: Date
    
    var attributedContent: NSAttributedString
    
    enum CodingKeys: String, CodingKey {
        case id, title, lastModified, rtfData
    }
    
    init(title: String = "Note mới", content: NSAttributedString = NSAttributedString(string: "")) {
        self.id = UUID()
        self.title = title
        self.lastModified = Date()
        self.attributedContent = content
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        
        if let data = try? container.decode(Data.self, forKey: .rtfData),
           let attrStr = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtfd],
               documentAttributes: nil
           ) {
            attributedContent = attrStr
        } else {
            attributedContent = NSAttributedString(string: "")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(lastModified, forKey: .lastModified)
        
        let range = NSRange(location: 0, length: attributedContent.length)
        let rtfData = (try? attributedContent.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )) ?? Data()
        
        try container.encode(rtfData, forKey: .rtfData)
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
        let currentNotes = self.notes
        let url = self.storeURL
        
        Task.detached(priority: .background) {
            guard let data = try? JSONEncoder().encode(currentNotes) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else {
            return
        }
        notes = decoded
    }

    private func nextNoteTitle() -> String {
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
