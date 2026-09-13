import Foundation
import AppKit
import Combine

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
    
    init(title: String = "Note mới", content: NSAttributedString = NSAttributedString(string: "")) {
        self.title = title
        self.contentData = (try? NSKeyedArchiver.archivedData(
            withRootObject: content,
            requiringSecureCoding: false
        )) ?? Data()
        self.lastModified = Date()
    }
}

@MainActor
class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedNoteID: UUID?
    
    private let saveKey = "MenuNotes.notes"
    
    init() {
        load()
        
        if notes.isEmpty {
            let first = Note(title: "Note 1")
            notes.append(first)
            selectedNoteID = first.id
        } else {
            // Mở note được cập nhật gần nhất
            selectedNoteID = notes.sorted { $0.lastModified > $1.lastModified }.first?.id
        }
    }
    
    var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }
    
    func addNote() {
        let newNote = Note(title: "Note \(notes.count + 1)")
        notes.append(newNote)
        selectedNoteID = newNote.id
        save()
    }
    
    func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        
        if selectedNoteID == note.id {
            selectedNoteID = notes.last?.id
        }
        save()
    }
    
    func renameNote(_ note: Note, newTitle: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[index].title = newTitle
        notes[index].lastModified = Date()
        save()
    }
    
    func updateContent(_ noteID: UUID, content: NSAttributedString) {
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else { return }
        notes[index].attributedContent = content
        notes[index].lastModified = Date()
        save()
    }
    
    func selectNote(_ note: Note) {
        selectedNoteID = note.id
        // Không cập nhật lastModified khi chỉ chọn tab
        // (chỉ cập nhật khi thực sự sửa nội dung hoặc đổi tên)
    }
    
    // MARK: - Persistence
    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([Note].self, from: data) else {
            return
        }
        notes = decoded
    }
}
