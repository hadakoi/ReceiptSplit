import UIKit
import SwiftData

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    let container: ModelContainer = {
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
            if testing { SavedPeople.resetForTesting(); SettlementStatus.resetForTesting() }
            return try ModelContainer(for: Receipt.self, ReceiptItem.self, Participant.self,
                                      configurations: ModelConfiguration(isStoredInMemoryOnly: testing))
        } catch { fatalError("Could not open receipt storage: \(error)") }
    }()
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.tintColor = .systemTeal
        window.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
}

extension UIViewController {
    var store: ModelContext { (UIApplication.shared.delegate as! AppDelegate).container.mainContext }
    func showError(_ message: String) {
        let alert = UIAlertController(title: "Couldn’t complete that action", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true)
    }
    @discardableResult func saveChanges() -> Bool {
        do { try store.save(); return true } catch { store.rollback(); showError(error.localizedDescription); return false }
    }
    func confirm(_ title: String, message: String, actionTitle: String = "Delete", action: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: actionTitle, style: .destructive) { _ in action() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); present(alert, animated: true)
    }
}
