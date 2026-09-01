//
//  SceneDelegate.swift
//  LittleSaver
//
//  Created by Rafael Soh on 24/8/22.
//

import SwiftUI

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    @Environment(\.openURL) var openURL

    func scene(
        _: UIScene,
        willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            guard let url = URL(string: shortcutItem.type), DeepLink(url: url) != nil else {
                return
            }

            openURL(url)
        }
    }

    func windowScene(
        _: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: shortcutItem.type), DeepLink(url: url) != nil else {
            completionHandler(false)
            return
        }

        openURL(url, completion: completionHandler)
    }
}
