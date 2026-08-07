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

    /// Tek yerde: `show()` bunu her açılışta yeniden atıyor (bkz.
    /// `orderFrontOnActiveSpace`), yani iki kopyası olamaz.
    private static let stripBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

    init(contentView view: NSView) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: Self.height),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        self.contentView = view
        isFloatingPanel = true
        level = .floating
        collectionBehavior = Self.stripBehavior
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
        orderFrontOnActiveSpace()
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

    /// Paneli öne alır ve AKTİF Space'e bağlandığını doğrular.
    ///
    /// `.canJoinAllSpaces` "her Space'te görün" demek, ama ortamda tam ekran
    /// bir Space varken pencere sunucusu paneli bazen tek bir Space'e
    /// iliştiriyor ve orada bırakıyor. Sonuç: AppKit'e göre pencere `isVisible`,
    /// çerçevesi de ekranla kesişiyor, ama kullanıcının baktığı Space'te
    /// ÇİZİLMİYOR. Bu haldeyken her kısayol basışı onu görünmeden aç/kapa
    /// yapıyor; kısayol da menüdeki "Open Stash" da ölü görünüyor ve tek çare
    /// uygulamayı yeniden başlatmak oluyor.
    ///
    /// Onarım: paneli geri çekip `collectionBehavior`ı yeniden atamak, pencere
    /// sunucusunu Space üyeliğini baştan hesaplamaya zorluyor.
    private func orderFrontOnActiveSpace() {
        makeKeyAndOrderFront(nil)
        guard !isOnActiveSpace else { return }
        orderOut(nil)
        collectionBehavior = []
        collectionBehavior = Self.stripBehavior
        makeKeyAndOrderFront(nil)
    }

    /// Panelin kullanıcının GERÇEKTEN gördüğü bir pencere olup olmadığı.
    /// Üç şartın üçü de ayrı bir hatadan geliyor:
    /// - `isVisible`: hiç açılmamış panel.
    /// - `isOnActiveSpace`: başka bir Space'e bağlanmış panel (yukarıya bak).
    /// - ekran kesişimi: animasyon çalışmadığı için ekranın altında kalmış panel.
    ///
    /// `toggleStrip` buna bakıyor: üçünden biri bile tutmuyorsa panel "kapalı"
    /// sayılır ve KAPATILMAK yerine yeniden gösterilir — yani her iki takılma
    /// durumu da bir sonraki basışta kendi kendini onarır.
    var isShowingOnScreen: Bool {
        stripIsShowing(isVisible: isVisible,
                       isOnActiveSpace: isOnActiveSpace,
                       panelFrame: frame,
                       screens: NSScreen.screens.map(\.visibleFrame))
    }

    func dismiss() {
        removeDismissMonitor()
        orderOut(nil)
        onDismiss?()
    }

    /// Kurtarılamayan paneli sessizce bırakır: `dismiss()` değil, çünkü bu bir
    /// kullanıcı eylemi değil — `onDismiss` çalışsaydı kullanıcının yazdığı
    /// süzgeç, panel daha görünmeden silinirdi.
    func retire() {
        removeDismissMonitor()
        orderOut(nil)
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

/// "Kullanıcı bu paneli şu anda görüyor mu?" sorusunun tamamı.
///
/// Ayrı ve saf: `NSWindow`un üç ayrı özelliğini birleştiren kural, gerçek bir
/// pencere ya da tam ekran bir Space kurmadan test edilebilsin diye. Kuralın
/// yönü kritik — şüphede kalırsak "kapalı" demeliyiz: yanlışlıkla "kapalı"
/// demek fazladan bir kez göstermek demek, yanlışlıkla "açık" demek ise şeridin
/// bir daha hiç açılmaması demek.
func stripIsShowing(isVisible: Bool, isOnActiveSpace: Bool,
                    panelFrame: NSRect, screens: [NSRect]) -> Bool {
    isVisible && isOnActiveSpace && stripIsOnScreen(panelFrame: panelFrame, screens: screens)
}
