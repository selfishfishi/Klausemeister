//
//  KlausemeisterApp.swift
//  Klausemeister
//
//  Created by Ali Fathalian on 4/4/26.
//

import SwiftUI

@main
struct KlausemeisterApp: App {
    @State private var windowState = WindowState()

    var body: some Scene {
        WindowGroup {
            TerminalContainerView(windowState: windowState)
        }
        .defaultSize(width: 800, height: 600)
    }
}
