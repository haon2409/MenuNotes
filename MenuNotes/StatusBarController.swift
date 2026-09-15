import Cocoa
import SwiftUI

class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var eventMonitor: EventMonitor?
    
    init() {
        // 1. Tạo status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // 2. Tạo popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 480, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())
        
        // 3. Gán icon vẽ dạng Apple Notes App Icon
        if let button = statusItem.button {
            button.image = createNotesAppIcon()
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        
        // 4. Event monitor (đóng khi click ra ngoài)
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, self.popover.isShown else { return }
            self.closePopover(event)
        }
        eventMonitor?.start()
    }
    
    deinit {
        eventMonitor?.stop()
    }
    
    // MARK: - Hàm vẽ Icon Apple Notes bằng Code Vector
    private func createNotesAppIcon() -> NSImage {
        // Thu nhỏ size tổng thể xuống 18x18 (90% của 20)
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.current?.saveGraphicsState()
            
            // Tự động scale toàn bộ nét vẽ xuống 90%
            let transform = NSAffineTransform()
            transform.scale(by: 0.9)
            transform.concat()
            
            // Giữ nguyên khung tọa độ ảo 20x20 để các thành phần không bị lệch
            let rect = NSRect(x: 0, y: 0, width: 20, height: 20)
            let cornerRadius: CGFloat = 4.5
            let basePath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            
            // 1. Nền trắng chính
            NSColor.white.setFill()
            basePath.fill()
            
            NSGraphicsContext.current?.saveGraphicsState()
            basePath.addClip()
            
            // 2. Phần nắp màu vàng/cam phía trên
            let headerHeight: CGFloat = 6.5
            let headerRect = NSRect(x: 0, y: rect.height - headerHeight, width: rect.width, height: headerHeight)
            NSColor(red: 254/255, green: 206/255, blue: 20/255, alpha: 1.0).setFill()
            NSBezierPath(rect: headerRect).fill()
            
            // 3. Đường chỉ kẻ mờ dưới nắp vàng
            let sepPath = NSBezierPath()
            sepPath.move(to: NSPoint(x: 0, y: rect.height - headerHeight))
            sepPath.line(to: NSPoint(x: rect.width, y: rect.height - headerHeight))
            NSColor.black.withAlphaComponent(0.15).setStroke()
            sepPath.lineWidth = 0.5
            sepPath.stroke()
            
            // 4. Hai dòng gạch ngang xám trên trang giấy
            NSColor(white: 0.78, alpha: 1.0).setStroke()
            
            let line1 = NSBezierPath()
            line1.move(to: NSPoint(x: 3.5, y: 9.5))
            line1.line(to: NSPoint(x: 16.5, y: 9.5))
            line1.lineWidth = 1.2
            line1.stroke()
            
            let line2 = NSBezierPath()
            line2.move(to: NSPoint(x: 3.5, y: 5.5))
            line2.line(to: NSPoint(x: 16.5, y: 5.5))
            line2.lineWidth = 1.2
            line2.stroke()
            
            NSGraphicsContext.current?.restoreGraphicsState() // Phục hồi clip
            
            // 5. Đường viền nét ngoài cùng
            NSColor.black.withAlphaComponent(0.2).setStroke()
            basePath.lineWidth = 0.5
            basePath.stroke()
            
            NSGraphicsContext.current?.restoreGraphicsState() // Phục hồi transform
            
            return true
        }
        image.isTemplate = false
        return image
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover(sender)
        }
    }
    
    func showPopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            eventMonitor?.start()
            NotificationCenter.default.post(name: .menuNotesDidShow, object: nil)
        }
    }
    
    func closePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }
}

// MARK: - EventMonitor
class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// MARK: - Notification
extension Notification.Name {
    static let menuNotesDidShow = Notification.Name("menuNotesDidShow")
}
