//
//  NotesEditorExampleView.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 23/11/26.
//

import SwiftUI

/// A clean SwiftUI example demonstrating native Apple Notes-like editing:
/// - Type with keyboard at any time.
/// - Speak with dictation bar to insert speech non-destructively.
/// - All speech errors pop up automatically.
struct NotesEditorExampleView: View {
    
    @State private var noteContent: String = "Meeting Agenda:\n1. Discuss Q4 goals\n2. "
    
    init() {}
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Native editable text view (type with keyboard at any time)
                TextEditor(text: $noteContent)
                    .font(.body)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .padding(.horizontal)
                
                // Drop-in Compact Speech Bar pinned at bottom above keyboard
                CompactSpeechBarView(text: $noteContent)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Notes Editor")
        }
    }
}

#Preview {
    NotesEditorExampleView()
}

