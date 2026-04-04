//
//  KlausemeisterApp.swift
//  Klausemeister
//
//  Created by Ali Fathalian on 4/4/26.
//

import SwiftUI

@main
struct KlausemeisterApp: App {
    var body: some Scene {
        WindowGroup {
            TerminalContainerView()
        }
        .defaultSize(width: 800, height: 600)
    }
}
