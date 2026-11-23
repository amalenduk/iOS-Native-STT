//
//  CompactSpeechBarLegacyView.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 23/11/26.
//

import SwiftUI
import UIKit

/// A compact, self-contained speech transcription bar designed specifically for legacy UIKit apps
/// and editable text views (like `UITextView` or `UITextField`).
/// Compatible with iOS 16+ using `ObservableObject` and `@ObservedObject`.
struct CompactSpeechBarLegacyView: View {
    
    // Clean Swift Store (ObservableObject)
    @ObservedObject private var store: SpeechTranscriptionStore
    
    // Optional weak reference to a UIKit UITextView for automatic cursor insertion
    private weak var targetTextView: UITextView?
    
    // Callbacks for custom text synchronization
    var onTextChange: ((_ fullText: String) -> Void)?
    var onAppendDelta: ((_ newWords: String) -> Void)?
    
    // Internal cursor tracking state for native Notes-style insertion
    @State private var startLocation: Int = 0
    @State private var uncommittedLength: Int = 0
    @State private var showingErrorAlert: Bool = false
    @State private var isPulsing: Bool = false
    
    // MARK: - Initializers
    
    /// Initializer for direct pairing with a UIKit UITextView (Automatic Apple Notes behavior)
    init(
        targetTextView: UITextView,
        store: SpeechTranscriptionStore? = nil
    ) {
        self.targetTextView = targetTextView
        self.store = store ?? SpeechTranscriptionStore()
        self.onTextChange = nil
        self.onAppendDelta = nil
    }
    
    /// Initializer using closures for custom sync (Option A / Option B)
    init(
        store: SpeechTranscriptionStore? = nil,
        onTextChange: ((_ fullText: String) -> Void)? = nil,
        onAppendDelta: ((_ deltaChunk: String) -> Void)? = nil
    ) {
        self.targetTextView = nil
        self.store = store ?? SpeechTranscriptionStore()
        self.onTextChange = onTextChange
        self.onAppendDelta = onAppendDelta
    }
    
    // MARK: - View Body
    
    var body: some View {
        HStack(spacing: 10) {
            // 1. Language Menu Button
            languageMenuButton
            
            // 2. Status / Live Interim Speech Preview
            centerStatusView
            
            // 3. Record / Stop Mic Button
            recordButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        )
        .overlay(
            Capsule()
                .strokeBorder(store.isRecording ? Color.red.opacity(0.35) : Color.gray.opacity(0.18), lineWidth: 1)
        )
        // Self-contained error alert
        .alert("Speech Recognition", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {
                store.clearError()
            }
        } message: {
            Text(store.errorMessage ?? "An error occurred during speech recognition.")
        }
        // iOS 16 compatible single-parameter .onChange
        .onChange(of: store.errorMessage) { newError in
            if newError != nil {
                showingErrorAlert = true
            }
        }
        // Live speech stream handler for cursor-specific insertion
        .onChange(of: store.fullTranscript) { newTranscript in
            handleIncomingSpeech(newTranscript)
        }
        .animation(.easeInOut(duration: 0.25), value: store.isRecording)
    }
    
    // MARK: - Subviews
    
    private var languageMenuButton: some View {
        Menu {
            Section("Supported Languages (\(store.supportedLocales.count))") {
                ForEach(store.supportedLocales) { item in
                    Button {
                        store.updateLocaleAndRestart(identifier: item.identifier)
                    } label: {
                        HStack {
                            Text(item.name)
                            if SpeechLocaleHelper.isEquivalent(store.selectedLocaleIdentifier, item.identifier) {
                                Image(systemName: "checkmark")
                            } else if !item.isInstalled {
                                Image(systemName: "icloud.and.arrow.down")
                            }
                        }
                    }
                }
            }
            
            if store.isModernEngineSupported {
                Section("Engine Mode") {
                    Button {
                        store.isUsingModernEngine.toggle()
                    } label: {
                        Label(
                            store.selectedEngineMode == .modern ? "Using Modern (Switch to Legacy)" : "Using Legacy (Switch to Modern)",
                            systemImage: store.selectedEngineMode == .modern ? "bolt.badge.sparkle" : "clock.arrow.circlepath"
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.caption2)
                Text(shortLanguageCode)
                    .font(.caption)
                    .fontWeight(.bold)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(store.isRecording ? .secondary : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(uiColor: .tertiarySystemBackground))
            )
        }
        .disabled(store.isRecording)
    }
    
    private var centerStatusView: some View {
        HStack(spacing: 6) {
            if store.isDownloadingModel {
                ProgressView()
                    .controlSize(.mini)
                Text("Downloading model...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if store.isPreparing {
                ProgressView()
                    .controlSize(.mini)
                Text("Starting...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if store.isRecording {
                // Pulsing indicator
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 1.25 : 0.85)
                    .opacity(isPulsing ? 1.0 : 0.6)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }
                    .onDisappear {
                        isPulsing = false
                    }
                
                if !store.partialText.isEmpty {
                    Text(store.partialText)
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text("Listening at cursor...")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                }
            } else {
                Text(store.selectedEngineMode == .modern ? "On-Device Dictation" : "SFSpeech Dictation")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var recordButton: some View {
        Button {
            toggleRecording()
        } label: {
            ZStack {
                if store.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 32, height: 32)
            .background(store.isRecording ? Color.red : Color.blue)
            .clipShape(Circle())
            .shadow(color: (store.isRecording ? Color.red : Color.blue).opacity(0.3), radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Native Notes-Style Cursor Insertion Logic
    
    private var shortLanguageCode: String {
        let id = store.selectedLocaleIdentifier.replacingOccurrences(of: "_", with: "-")
        let components = id.split(separator: "-")
        return (components.first ?? "EN").uppercased()
    }
    
    private func toggleRecording() {
        if store.isRecording {
            finalizeCursorInsertion()
            store.stop()
        } else {
            if let textView = targetTextView {
                self.startLocation = textView.selectedRange.location
                self.uncommittedLength = 0
            }
            store.clearTranscript()
            store.start()
        }
    }
    
    private func handleIncomingSpeech(_ fullTranscript: String) {
        guard store.isRecording else { return }
        let speech = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speech.isEmpty else { return }
        
        // Mode 1: Automatic UITextView insertion at active cursor (Apple Notes style)
        if let textView = targetTextView {
            let rangeToReplace = NSRange(location: startLocation, length: uncommittedLength)
            
            // Add leading space if preceding character is not whitespace or newline
            let needsLeadingSpace: Bool
            if startLocation > 0 && rangeToReplace.length == 0 {
                let text = textView.text as NSString?
                if let text, startLocation <= text.length {
                    let prevChar = text.substring(with: NSRange(location: startLocation - 1, length: 1))
                    needsLeadingSpace = prevChar != " " && prevChar != "\n"
                } else {
                    needsLeadingSpace = false
                }
            } else {
                needsLeadingSpace = false
            }
            
            let textToInsert = (needsLeadingSpace ? " " : "") + speech
            
            textView.selectedRange = rangeToReplace
            textView.insertText(textToInsert)
            
            self.uncommittedLength = (textToInsert as NSString).length
        }
        
        // Mode 2: Custom callback forwarding
        self.onTextChange?(speech)
        self.onAppendDelta?(speech)
    }
    
    private func finalizeCursorInsertion() {
        if let textView = targetTextView {
            self.startLocation = textView.selectedRange.location
            self.uncommittedLength = 0
        }
        store.clearTranscript()
    }
    
    // MARK: - UIKit Helper
    
    @MainActor
    func makeInputAccessoryView(width: CGFloat = UIScreen.main.bounds.width) -> UIView {
        let hostingController = UIHostingController(rootView: self)
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = CGRect(x: 0, y: 0, width: width, height: 56)
        return hostingController.view
    }
}
