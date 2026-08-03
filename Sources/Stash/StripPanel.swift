import AppKit

/// Şerit penceresi. Üç ayar bu sınıfın tamamının varlık sebebi:
/// - .nonactivatingPanel: panel açılınca öndeki uygulama önde kalır, yoksa
///   geri yapıştıracağımız uygulama arkaya düşer ve ⌘V yanlış yere gider.
/// - .canJoinAllSpaces: Space değiştirince pencere kendi Space'ine zıplamaz.
/// - .fullScreenAuxiliary: tam ekran uygulamaların üstünde de görünür.
final class StripPanel: NSPanel {
    var onDismiss: (() -> Void)?
    private var monitor: Any?

    static let height: CGFloat = 300

    init(contentView view: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: Self.height),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        self.contentView = view
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }

    func show(on screen: NSScreen) {
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                           width: screen.frame.width, height: Self.height)
        // Aşağıdan yukarı kayma: önce ekranın altına gizle, sonra yerine sür.
        setFrame(frame.offsetBy(dx: 0, dy: -Self.height), display: false)
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: true)
        }
        installDismissMonitor()
    }

    func dismiss() {
        removeDismissMonitor()
        orderOut(nil)
        onDismiss?()
    }

    /// Dışarı tıklamayı yakalar. Panel key olduğu için resignKey tek başına
    /// yetmiyor: kullanıcı başka uygulamaya tıkladığında da kapanmalı.
    private func installDismissMonitor() {
        removeDismissMonitor()
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeDismissMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }
}
