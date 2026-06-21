//
//  ContentView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @State private var showSettings = false
    @ObservedObject private var preferences = UserPreferences.shared

    var body: some View {
        Group {
            if !preferences.hasCompletedOnboarding {
                OnboardingView()
            } else {
                VoiceInputView()
                    .frame(minWidth: 560, minHeight: 520)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button(action: { showSettings = true }) {
                                Label(NSLocalizedString("settings", comment: ""), systemImage: "gearshape")
                            }
                            .help(NSLocalizedString("settings", comment: ""))
                            .focusable(false)
                        }
                    }
                    .sheet(isPresented: $showSettings) {
                        SettingsView()
                            .frame(minWidth: 800, idealWidth: 900, maxWidth: 1000, minHeight: 600, idealHeight: 700, maxHeight: 800)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                        showSettings = true
                    }
            }
        }
        .onChange(of: preferences.hasCompletedOnboarding) { _, completed in
            if completed {
                SpeechModelPreloadManager.shared.startPreloadIfNeeded()
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

#Preview {
    ContentView()
}
