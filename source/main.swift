import UIKit

final class FixtureController: UIViewController {
    private let dot = UIView(frame: CGRect(x: 20, y: 110, width: 20, height: 20))
    private let moving = UserDefaults.standard.string(forKey: "mode") == "moving"
    private var displayLink: CADisplayLink?
    private var start: CFTimeInterval?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let scroll = UIScrollView(frame: view.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.accessibilityIdentifier = "repro-scroll"
        scroll.contentSize = CGSize(width: view.bounds.width, height: view.bounds.height * 3)
        view.addSubview(scroll)

        let rows: [(String, String, CGFloat)] = [
            ("First row", "repro-first-row", 200),
            ("Second row", "repro-second-row", view.bounds.height + 80),
            ("Third row", "repro-third-row", view.bounds.height * 2)
        ]
        for (text, identifier, y) in rows {
            let label = UILabel(frame: CGRect(x: 24, y: y, width: 280, height: 44))
            label.text = text
            label.font = .systemFont(ofSize: 24)
            label.accessibilityIdentifier = identifier
            scroll.addSubview(label)
        }

        dot.backgroundColor = .systemBlue
        dot.layer.cornerRadius = 10
        dot.isUserInteractionEnabled = false
        dot.isAccessibilityElement = true
        dot.accessibilityLabel = "Blue dot"
        dot.accessibilityIdentifier = "repro-dot"
        view.addSubview(dot)

        displayLink = CADisplayLink(target: self, selector: #selector(frame(_:)))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func frame(_ link: CADisplayLink) {
        if start == nil { start = link.timestamp }
        guard moving, let start else { return }
        // Travel at 6 pt/s, reversing every 30 seconds without a position jump.
        let phase = (link.timestamp - start).truncatingRemainder(dividingBy: 60)
        dot.frame.origin.x = 20 + CGFloat(min(phase, 60 - phase) * 6)
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        window?.rootViewController = FixtureController()
        window?.makeKeyAndVisible()
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Fixture", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil,
                  NSStringFromClass(AppDelegate.self))
