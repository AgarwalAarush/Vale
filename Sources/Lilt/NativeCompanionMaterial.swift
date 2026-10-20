import AppKit

/// A real system glass surface on macOS 26, with native backdrop material on
/// macOS 14/15. The stable hosting view belongs to the effect's content view;
/// arbitrary NSGlassEffectView subviews do not have guaranteed glass ordering.
@MainActor final class NativeCompanionMaterial: NSView {
    private let effect: NSView
    private let effectContent = NSView()
    private let solidSurface = NSView()
    private var accessibilityObserver: NSObjectProtocol?
    var cornerRadius: CGFloat = 24 {
        didSet {
            layer?.cornerRadius = cornerRadius
            if #available(macOS 26, *), let glass = effect as? NSGlassEffectView { glass.cornerRadius = cornerRadius }
        }
    }
    var usesLiquidGlass: Bool {
        if #available(macOS 26, *) { return effect is NSGlassEffectView }
        return false
    }

    override init(frame frameRect: NSRect) {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: frameRect.size))
            glass.style = .regular
            glass.cornerRadius = 24
            effect = glass
        } else {
            let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: frameRect.size))
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            effect = material
        }
        super.init(frame: frameRect)
        if #available(macOS 26, *), let glass = effect as? NSGlassEffectView { glass.contentView = effectContent }
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        addSubview(effect)
        effectContent.frame = bounds
        effectContent.autoresizingMask = [.width, .height]
        if !usesLiquidGlass { effect.addSubview(effectContent) }
        solidSurface.frame = bounds
        solidSurface.autoresizingMask = [.width, .height]
        solidSurface.wantsLayer = true
        effectContent.addSubview(solidSurface)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refreshAccessibility() } }
        refreshAccessibility()
    }
    required init?(coder: NSCoder) { nil }
    deinit { if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) } }
    func installContentView(_ view: NSView) {
        view.frame = effectContent.bounds
        view.autoresizingMask = [.width, .height]
        effectContent.addSubview(view)
    }
    func refreshAccessibility() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        // One neutral reading plane behind *all* routes bounds the amount of
        // desktop color that can enter the glass. Keep the native edge/effect;
        // never add a second panel stroke to imitate it.
        let color = Theme.resolved(Theme.companionSurfaceColor, in: effectiveAppearance)
        solidSurface.isHidden = false
        solidSurface.layer?.backgroundColor = color.withAlphaComponent(reduce || contrast ? 1 : 0.90).cgColor
        if #available(macOS 26, *), let glass = effect as? NSGlassEffectView {
            glass.tintColor = color.withAlphaComponent(0.08)
        }
        if let material = effect as? NSVisualEffectView { material.state = reduce ? .inactive : .active }
        needsDisplay = true
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAccessibility()
    }
}
