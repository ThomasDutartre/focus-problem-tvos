import SwiftUI

struct ContentView: View {
    var body: some View {
        TabBarControllerRepresentable()
            .ignoresSafeArea()
    }
}

struct TabBarControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITabBarController {
        let tabBarController = FocusRedirectingTabBarController()

        // Wrap in UINavigationController like the real app
        let focusTrapVC = FocusProblemViewController()
        let navController = UINavigationController(rootViewController: focusTrapVC)
        navController.isNavigationBarHidden = true
        navController.tabBarItem = UITabBarItem(title: "Focus Trap", image: nil, tag: 0)

        let placeholderVC = UIViewController()
        placeholderVC.view.backgroundColor = .darkGray
        placeholderVC.tabBarItem = UITabBarItem(title: "Other", image: nil, tag: 1)

        tabBarController.viewControllers = [navController, placeholderVC]
        return tabBarController
    }

    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {}
}

/// Lets the bench move focus programmatically from anywhere (including from the tab bar):
/// a focus update request is only honored when issued by an environment containing the focused item.
final class FocusRedirectingTabBarController: UITabBarController {
    var focusRedirect: UIFocusEnvironment?

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let focusRedirect { return [focusRedirect] }
        return super.preferredFocusEnvironments
    }

    func moveFocus(to environment: UIFocusEnvironment) {
        focusRedirect = environment
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
        focusRedirect = nil
    }
}
