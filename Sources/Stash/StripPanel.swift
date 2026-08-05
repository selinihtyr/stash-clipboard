import AppKit

/// Şerit penceresi. Üç ayar bu sınıfın tamamının varlık sebebi:
/// - .nonactivatingPanel: panel açılınca öndeki uygulama önde kalır, yoksa
///   geri yapıştıracağımız uygulama arkaya düşer ve ⌘V yanlış yere gider.
/// - .canJoinAllSpaces: Space değiştirince pencere kendi Space'ine zıplamaz.
/// - .fullScreenAuxiliary: tam ekran uygulamaların üstünde de görünür.
final class StripPanel: NSPanel {
    var onDismiss: (() -> Void)?
    /// Ham NSEvent burada saf stripCommand(...) eşlemesine çevrilip
    /// yönlendiriliyor. true dönerse tuş yutulur (super'e gitmez); false
    /// dönerse super.keyDown çalışır — böylece işlemediğimiz tuşlarda sistem
    /// beep sesi yerine normal davranış (ya da sessizlik) olur.
    var onKey: ((NSEvent) -> Bool)?
    private var monitor: Any?

    /// Theme'den türetiliyor: sabit bir sayı, başlık büyüdüğünde seçili kartı
    /// sessizce kırpıyordu.
    static var height: CGFloat { Theme.stripHeight }

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

    override func keyDown(with event: NSEvent) {
        // Panel key olduğu için bütün tuşlar buraya düşer; işlemediğimizi
        // super'e bırakıyoruz ki sistem sesleri boşuna çalmasın.
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    func show(on screen: NSScreen) {
        // visibleFrame, frame değil: ekranın mutlak alt kenarına oturursak Dock
        // şeridin altını örter ve kartların bir kısmı okunmaz olur. visibleFrame
        // Dock'un (ve gizlenmiyorsa menü çubuğunun) kapladığı alanı zaten dışlıyor.
        let area = screen.visibleFrame
        let frame = NSRect(x: area.minX, y: area.minY,
                           width: area.width, height: Self.height)
        // Aşağıdan yukarı kayma: önce ekranın altına gizle, sonra yerine sür.
        setFrame(frame.offsetBy(dx: 0, dy: -Self.height), display: false)
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            // Son kare GARANTİ altına alınıyor. Animasyon her zaman çalışmıyor:
            // ekran uykudan yeni uyandığında, Erişilebilirlik > "Hareketi azalt"
            // açıkken ya da pencere sunucusu animasyonları bastırdığında
            // `animator()` hiçbir şey yapmıyor ve panel BAŞLANGIÇ konumunda —
            // ekranın altında — kalıyor. Görünmüyor ama `isVisible` true, yani
            // bir sonraki kısayol basışı onu "kapatıyor": kullanıcı için şerit
            // bir daha hiç açılmıyor, üstelik menüden de açılmıyor. Ekranı
            // uyutup uyandırarak birebir üretildi.
            self?.setFrame(frame, display: true)
        })
        installDismissMonitor()
    }

    /// Panelin gerçekten ekranda olup olmadığı. `isVisible` tek başına
    /// yetmiyor: yukarıdaki takılma durumunda pencere "görünür" ama ekranın
    /// dışında. `toggleStrip` buna bakmasa, takılmış bir paneli kapatmaya
    /// çalışır ve kullanıcı şeridi bir daha hiç göremezdi.
    var isShowingOnScreen: Bool {
        isVisible && stripIsOnScreen(panelFrame: frame,
                                     screens: NSScreen.screens.map(\.visibleFrame))
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

/// Panelin herhangi bir ekranın görünür alanıyla kesişip kesişmediği.
///
/// Ayrı ve saf bir fonksiyon: gerçek bir ekran ya da pencere olmadan test
/// edilebilsin diye. Kesişim şartı "tamamen içinde" değil — şerit, ekranın
/// altına gizlenmiş halde bile bir pikselle kesişmemeli, ama iki ekran
/// arasında yarım kalan bir panel de görünür sayılmalı.
func stripIsOnScreen(panelFrame: NSRect, screens: [NSRect]) -> Bool {
    screens.contains { $0.intersects(panelFrame) }
}
