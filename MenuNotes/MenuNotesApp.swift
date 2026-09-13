import SwiftUI

@main
struct MenuNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() } // ẩn cửa sổ Settings mặc định
    }
}
