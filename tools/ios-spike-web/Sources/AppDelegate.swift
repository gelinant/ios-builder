import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var runner: SpikeRunner?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        setvbuf(stdout, nil, _IOLBF, 0)
        let w = UIWindow(frame: UIScreen.main.bounds)
        let vc = UIViewController()
        vc.view.backgroundColor = .white
        let label = UILabel(frame: CGRect(x: 8, y: 50, width: w.bounds.width - 16, height: 40))
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.numberOfLines = 2
        label.text = "W-2 spike"
        vc.view.addSubview(label)
        w.rootViewController = vc
        w.makeKeyAndVisible()
        window = w
        let r = SpikeRunner(host: vc.view, status: label)
        runner = r
        let args = Array(CommandLine.arguments.dropFirst())
        Task { @MainActor in
            await r.runAll(args: args)
        }
        return true
    }
}
