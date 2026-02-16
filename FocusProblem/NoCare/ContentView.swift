import SwiftUI

struct ContentView: View {
    var body: some View {
        TabBarControllerRepresentable()
            .ignoresSafeArea()
    }
}

struct TabBarControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITabBarController {
        let tabBarController = UITabBarController()

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
