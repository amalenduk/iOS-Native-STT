//
//  CompactSpeechBarView.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 23/11/26.
//

import SwiftUI

/// A self-contained, drop-in compact speech transcription bar designed for easy integration into legacy screens.
/// Compatible with iOS 16+ using `ObservableObject` and `@ObservedObject`.
struct CompactSpeechBarView: View {
    
    // Optional binding to an editable text string (e.g. from TextEditor or TextField)
    @Binding private var externalText: String
    private let hasExternalBinding: Bool
    
    // Callbacks for UIKit or custom host integration
    var onTextChange: ((_ fullText: String) -> Void)?
    
    // Clean Swift Store (ObservableObject)
    @ObservedObject private var store: SpeechTranscriptionStore
    
    // Internal snapshot for non-destructive appending
    @State private var baseTextSnapshot: String = ""
    @State private var showingErrorAlert: Bool = false
    @State private var isPulsing: Bool = false
    
    /// Initializer for SwiftUI views binding directly to an editable string
    init(
        text: Binding<String>,
        store: SpeechTranscriptionStore? = nil,
        onTextChange: ((_ fullText: String) -> Void)? = nil
    ) {
        self._externalText = text
        self.hasExternalBinding = true
        self.store = store ?? SpeechTranscriptionStore()
        self.onTextChange = onTextChange
    }
    
    /// Initializer for standalone use (or UIKit UIHostingController wrapping with closures)
    init(
        store: SpeechTranscriptionStore? = nil,
        onTextChange: ((_ fullText: String) -> Void)? = nil
    ) {
        self._externalText = .constant("")
        self.hasExternalBinding = false
        self.store = store ?? SpeechTranscriptionStore()
        self.onTextChange = onTextChange
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // 1. Language Selector Button
            languageMenuButton
            
            // 2. Center Status / Speech Waveform Indicator
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
        // Self-contained Error Alert
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
        // Non-destructive live text sync
        .onChange(of: store.fullTranscript) { newTranscript in
            handleTranscriptUpdate(newTranscript)
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
                Text("Downloading language...")
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
                // Pulsing red indicator
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
                
                // Live volatile preview or "Listening..."
                if !store.partialText.isEmpty {
                    Text(store.partialText)
                        .font(.caption2)
                        .italic()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text("Listening...")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                }
            } else {
                Text(store.selectedEngineMode == .modern ? "On-Device Speech" : "SFSpeech Cloud")
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
    
    // MARK: - Logic & Sync Handling
    
    private var shortLanguageCode: String {
        let id = store.selectedLocaleIdentifier.replacingOccurrences(of: "_", with: "-")
        let components = id.split(separator: "-")
        return (components.first ?? "EN").uppercased()
    }
    
    private func toggleRecording() {
        if store.isRecording {
            finalizeTextSync()
            store.stop()
        } else {
            if hasExternalBinding {
                self.baseTextSnapshot = externalText
            }
            store.clearTranscript()
            store.start()
        }
    }
    
    private func handleTranscriptUpdate(_ fullTranscript: String) {
        guard store.isRecording else { return }
        let speech = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speech.isEmpty else { return }
        
        if hasExternalBinding {
            let separator: String
            if baseTextSnapshot.isEmpty {
                separator = ""
            } else if baseTextSnapshot.hasSuffix(" ") || baseTextSnapshot.hasSuffix("\n") {
                separator = ""
            } else {
                separator = " "
            }
            let combined = baseTextSnapshot + separator + speech
            self.externalText = combined
            self.onTextChange?(combined)
        } else {
            self.onTextChange?(speech)
        }
    }
    
    private func finalizeTextSync() {
        if hasExternalBinding {
            self.baseTextSnapshot = externalText
        }
        store.clearTranscript()
    }
}
