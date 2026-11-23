//
//  NativeSpeechContentView.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import SwiftUI

struct NativeSpeechContentView: View {
    
    @ObservedObject var store: SpeechTranscriptionStore
    
    init(store: SpeechTranscriptionStore) {
        self.store = store
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Engine Switch Control (Toggle between Modern and Legacy)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: store.selectedEngineMode == .modern ? "bolt.badge.sparkle" : "clock.arrow.circlepath")
                                .foregroundStyle(store.selectedEngineMode == .modern ? .blue : .orange)
                            
                            Text(store.selectedEngineMode == .modern ? "Modern Engine (iOS 26+)" : "Legacy Engine (SFSpeech)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        Text(store.selectedEngineMode == .modern ? "SpeechAnalyzer & Foundation Transcriber" : "SFSpeechRecognizer Audio Stream")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        if !store.isModernEngineSupported {
                            Text("Modern engine requires iOS 26 or later")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $store.isUsingModernEngine)
                        .labelsHidden()
                        .disabled(!store.isModernEngineSupported)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
                )
                
                // Error Banner / Display
                if let errorMessage = store.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Error")
                                .font(.headline)
                                .foregroundStyle(.red)
                            
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            store.clearError()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Status & Language Header
                HStack {
                    if store.isDownloadingModel {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Downloading Model...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if store.isPreparing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Starting...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(store.isRecording ? Color.red : Color.gray)
                                .frame(width: 10, height: 10)
                            
                            Text(store.isRecording ? "Listening..." : (store.isStopping ? "Stopping..." : "Idle"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(store.isRecording ? .red : .secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Locale Selector Menu
                    Menu {
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
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(store.selectedLocaleDisplayName)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.blue.opacity(0.12)))
                        .foregroundStyle(.blue)
                    }
                }
                
                // Active Engine Identifier & Tokens Bar
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                        Text(store.engineDescription)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if !store.tokens.isEmpty {
                        Text("\(store.tokens.count) tokens")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Full Transcript Section
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Live Transcript")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if !store.fullTranscript.isEmpty {
                            HStack(spacing: 12) {
                                Button("Copy") {
                                    UIPasteboard.general.string = store.fullTranscript
                                }
                                .font(.caption)
                                
                                Button("Clear") {
                                    store.clearTranscript()
                                }
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                        }
                    }
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(store.fullTranscript.isEmpty ? "Transcription will appear here..." : store.fullTranscript)
                                .font(.body)
                                .foregroundStyle(store.fullTranscript.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding()
                                .id("bottom")
                        }
                        .onChange(of: store.fullTranscript) { _ in
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // Partial Text Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Partial / In-Progress")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(store.partialText.isEmpty ? "—" : store.partialText)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(store.partialText.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if store.isRecording && !store.partialText.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // Controls: Start / Stop Buttons
                HStack(spacing: 16) {
                    Button {
                        store.start()
                    } label: {
                        Label("Start", systemImage: "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(store.isRecording || store.isStopping || store.isPreparing)
                    
                    Button {
                        store.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!store.isRecording || store.isStopping)
                }
                .padding(.top, 4)
            }
            .padding()
            .navigationTitle("Live Speech")
        }
    }
}

#Preview {
    NativeSpeechContentView(store: SpeechTranscriptionStore())
}
