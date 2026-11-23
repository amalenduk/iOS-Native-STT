//
//  ContentView.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import SwiftUI
import UIKit

/// Bridge to host the legacy UIKit `LegacyNotesEditorViewController` with `CompactSpeechBarLegacyView`.
struct LegacyNotesEditorRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let editorVC = LegacyNotesEditorViewController()
        let navController = UINavigationController(rootViewController: editorVC)
        navController.navigationBar.prefersLargeTitles = false
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

struct ContentView: View {
    @StateObject private var store = SpeechTranscriptionStore()
    @State private var selectedTab: Int = 0
    
    init() {}
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Legacy UIKit Notes Editor with CompactSpeechBarLegacyView (Default)
            LegacyNotesEditorRepresentable()
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .tabItem {
                    Label("Legacy Notes", systemImage: "note.text")
                }
                .tag(0)
            
            // Tab 2: SwiftUI Notes Editor Example
            NotesEditorExampleView()
                .tabItem {
                    Label("SwiftUI Notes", systemImage: "pencil.and.outline")
                }
                .tag(1)
            
            // Tab 3: Full Native Speech Inspector
            NativeSpeechContentView(store: store)
                .tabItem {
                    Label("Speech Inspector", systemImage: "waveform")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
}
