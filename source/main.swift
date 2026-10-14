import UIKit
import QuartzCore

func record(_ name: String, _ fields: [String: Any] = [:]) {
    var entry = fields
    entry["event"] = name
    entry["wall"] = Date().timeIntervalSince1970
    entry["uptime"] = ProcessInfo.processInfo.systemUptime
    guard let bytes = try? JSONSerialization.data(withJSONObject: entry),
          let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let file = folder.appendingPathComponent("events.jsonl")
    if !FileManager.default.fileExists(atPath: file.path) {
        _ = FileManager.default.createFile(atPath: file.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: file) else { return }
    handle.seekToEndOfFile()
    handle.write(bytes)
    handle.write(Data([10]))
    try? handle.close()
}

@objc(FixtureApplication)
final class FixtureApplication: UIApplication {
    override func sendEvent(_ event: UIEvent) {
        for touch in event.allTouches ?? [] where touch.phase == .began {
            record("touchBegan", ["eventUptime": event.timestamp,
                "dispatchLagMs": (ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000])
        }
        super.sendEvent(event)
    }
}

final class FixtureController: UIViewController, UIScrollViewDelegate {
    private let moving = UserDefaults.standard.string(forKey: "mode") == "moving"
    private let scroll = UIScrollView()
    private let ready = UILabel()
    private let scrolled = UILabel()
    private let thumb = UIView()
    private var displayLink: CADisplayLink?
    private var previousFrame: CFTimeInterval = 0
    private var sampleStart: CFTimeInterval = 0
    private var maximumGap: CFTimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("events.jsonl")
        try? Data().write(to: file)
        view.backgroundColor = .white
        view.accessibilityIdentifier = "repro-root"
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.accessibilityIdentifier = "repro-scroll"
        scroll.delegate = self
        view.addSubview(scroll)
        for i in 0..<24 {
            let label = UILabel(frame: CGRect(x: 24, y: 30 + i * 80, width: 300, height: 60))
            label.text = "Row \(i)"
            label.font = .systemFont(ofSize: 24)
            label.accessibilityIdentifier = "repro-row-\(i)"
            scroll.addSubview(label)
        }
        scroll.contentSize = CGSize(width: view.bounds.width, height: 1950)
        ready.frame = CGRect(x: 20, y: 70, width: 240, height: 40)
        ready.text = "Ready"
        ready.backgroundColor = .white
        ready.accessibilityIdentifier = "repro-ready"
        view.addSubview(ready)
        scrolled.frame = CGRect(x: 20, y: 110, width: 240, height: 30)
        scrolled.text = "Scrolled"
        scrolled.backgroundColor = .white
        scrolled.accessibilityIdentifier = "repro-scrolled"
        scrolled.isHidden = true
        view.addSubview(scrolled)
        if moving {
            thumb.frame = CGRect(x: 20, y: 150, width: 20, height: 20)
            thumb.backgroundColor = .systemBlue
            thumb.layer.cornerRadius = 10
            thumb.isUserInteractionEnabled = false
            thumb.isAccessibilityElement = true
            thumb.accessibilityLabel = "Moving thumb"
            thumb.accessibilityIdentifier = "repro-moving-thumb"
            view.addSubview(thumb)
        }
        displayLink = CADisplayLink(target: self, selector: #selector(frame(_:)))
        displayLink?.add(to: .main, forMode: .common)
        record("ready", ["mode": moving ? "moving" : "bare"])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.contentSize.width = view.bounds.width
    }

    @objc private func frame(_ link: CADisplayLink) {
        if moving { thumb.frame.origin.x = 20 + CGFloat(link.timestamp.truncatingRemainder(dividingBy: 30) * 6) }
        if previousFrame > 0 { maximumGap = max(maximumGap, link.timestamp - previousFrame) }
        previousFrame = link.timestamp
        if sampleStart == 0 { sampleStart = link.timestamp }
        if link.timestamp - sampleStart >= 1 {
            record("frames", ["maxIntervalMs": maximumGap * 1000])
            sampleStart = link.timestamp
            maximumGap = 0
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        record("scrollBegin", ["offset": scrollView.contentOffset.y])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y > 10 && scrolled.isHidden {
            scrolled.isHidden = false
            record("scrolled", ["offset": scrollView.contentOffset.y])
        }
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        window?.rootViewController = FixtureController()
        window?.makeKeyAndVisible()
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Fixture", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, NSStringFromClass(FixtureApplication.self), NSStringFromClass(AppDelegate.self))
