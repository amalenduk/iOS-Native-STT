//
//  SpeechTranscriptionStore.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 23/11/26.
//

import Combine
import Foundation
import os

/// A Clean Swift ObservableObject Store managing live speech-to-text state and actions.
/// Compatible with iOS 16+ (using `@Published` and `ObservableObject` instead of the iOS 17 `@Observable` macro).
@MainActor
final class SpeechTranscriptionStore: ObservableObject {
    
    // MARK: - State Properties (@Published for iOS 16+)
    
    @Published var selectedEngineMode: SpeechEngineMode {
        didSet {
            SpeechLog.store.info("Switched to engine: \(self.selectedEngineMode.rawValue)")
        }
    }
    
    @Published var isRecording: Bool = false
    @Published var isStopping: Bool = false
    @Published var isPreparing: Bool = false
    @Published var errorMessage: String? = nil
    
    @Published var selectedLocale: Locale = Locale.current
    @Published var selectedLocaleIdentifier: String = Locale.current.identifier
    @Published var supportedLocales: [LocaleItem] = SpeechLocaleHelper.defaultLocaleItems
    
    @Published var fullTranscript: String = ""
    @Published var partialText: String = ""
    @Published var finalizedText: String = ""
    @Published var tokens: [SpeechTranscriptionToken] = []
    
    @Published var isDownloadingModel: Bool = false
    @Published var downloadProgress: Progress? = nil
    
    // MARK: - Dependencies & Private Pipeline
    
    private var transcriber: any SpeechTranscriptionService
    private let recorder: NativeSpeechRecorder
    private var streamingTask: Task<Void, Never>?
    
    // MARK: - Computed Properties
    
    var isModernEngineSupported: Bool {
        SpeechLocaleHelper.isModernSupported
    }
    
    var isUsingModernEngine: Bool {
        get { selectedEngineMode == .modern }
        set {
            let targetMode: SpeechEngineMode = newValue ? .modern : .legacy
            switchEngine(to: targetMode)
        }
    }
    
    var selectedLocaleDisplayName: String {
        Locale.current.localizedString(forIdentifier: selectedLocaleIdentifier)
            ?? selectedLocaleIdentifier
    }
    
    var engineDescription: String {
        transcriber.engineDescription
    }
    
    // MARK: - Initializer (Dependency Injection)
    
    init(
        transcriber: (any SpeechTranscriptionService)? = nil,
        engineMode: SpeechEngineMode? = nil,
        recorder: NativeSpeechRecorder? = nil
    ) {
        self.recorder = recorder ?? NativeSpeechRecorder()
        let initialMode = engineMode ?? (SpeechLocaleHelper.isModernSupported ? .modern : .legacy)
        self.selectedEngineMode = initialMode
        let service = transcriber ?? SpeechTranscriptionServiceFactory.makeService(forceLegacy: initialMode == .legacy)
        self.transcriber = service
        setupServiceBindings(for: service)
        
        Task {
            await loadSupportedLocales()
            resolveLocaleForActiveEngine()
        }
    }
    
    // MARK: - Actions / Intents
    
    /// Switch transcription engine on the fly (Modern SpeechAnalyzer vs Legacy SFSpeechRecognizer)
    func switchEngine(to mode: SpeechEngineMode) {
        guard mode != selectedEngineMode else { return }
        
        if mode == .modern && !isModernEngineSupported {
            errorMessage = "Modern SpeechAnalyzer engine requires iOS 26 or later."
            return
        }
        
        let wasRecording = isRecording
        if wasRecording {
            stop()
        }
        
        self.selectedEngineMode = mode
        let forceLegacy = (mode == .legacy)
        let newService = SpeechTranscriptionServiceFactory.makeService(forceLegacy: forceLegacy)
        self.transcriber = newService
        setupServiceBindings(for: newService)
        
        Task {
            await loadSupportedLocales()
            resolveLocaleForActiveEngine()
            
            if wasRecording {
                try? await Task.sleep(nanoseconds: 300_000_000)
                start()
            }
        }
    }
    
    /// Starts live audio streaming and speech recognition
    func start() {
        guard !isRecording, !isStopping, !isPreparing else { return }
        errorMessage = nil
        isPreparing = true
        
        streamingTask = Task {
            do {
                try await transcriber.setUpTranscriber(locale: selectedLocale)
                isPreparing = false
                isRecording = true
                
                let stream = try await recorder.startStreaming()
                for await buffer in stream {
                    guard !Task.isCancelled else { break }
                    try transcriber.streamAudioBuffer(buffer)
                }
            } catch {
                if !Task.isCancelled {
                    self.handleRuntimeError(error)
                    SpeechLog.store.error("Transcription error: \(error.localizedDescription)")
                }
            }
            self.isRecording = false
            self.isPreparing = false
        }
    }
    
    /// Stops audio capture and finalizes recognition
    func stop() {
        guard isRecording, !isStopping else { return }
        isStopping = true
        
        streamingTask?.cancel()
        streamingTask = nil
        
        Task {
            recorder.stop()
            try? await transcriber.finishTranscribing()
            syncTranscriptFromService()
            self.isRecording = false
            self.isStopping = false
        }
    }
    
    /// Clears both transcriber and internal transcript buffers
    func clearTranscript() {
        transcriber.clear()
        syncTranscriptFromService()
        errorMessage = nil
    }
    
    /// Clears any active error message
    func clearError() {
        errorMessage = nil
    }
    
    /// Updates the selected locale and restarts transcription if active
    func updateLocaleAndRestart(identifier: String) {
        setLocale(identifier: identifier)
        let wasRecording = isRecording
        
        if wasRecording {
            stop()
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                start()
            }
        }
    }
    
    /// Sets locale and updates state
    func setLocale(identifier: String) {
        self.selectedLocaleIdentifier = identifier
        self.selectedLocale = Locale(identifier: identifier)
    }
    
    // MARK: - Private Helper Methods
    
    private func setupServiceBindings(for service: any SpeechTranscriptionService) {
        service.onTranscriptUpdate = { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncTranscriptFromService()
            }
        }
        service.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleRuntimeError(error)
            }
        }
        syncTranscriptFromService()
    }
    
    private func syncTranscriptFromService() {
        self.finalizedText = transcriber.finalizedText
        self.partialText = transcriber.volatileText
        self.fullTranscript = transcriber.fullTranscript
        self.tokens = transcriber.tokens
        self.isDownloadingModel = transcriber.isDownloadingModel
        self.downloadProgress = transcriber.downloadProgress
    }
    
    private func handleRuntimeError(_ error: Error) {
        let desc = error.localizedDescription
        if desc.localizedCaseInsensitiveContains("No space left on device")
            || desc.contains("201")
            || (error as NSError).domain == "EARErrorDomain" {
            self.errorMessage = "Device Storage Full: On-device speech recognition requires free disk space to compile neural models. Please free up storage in iPhone Settings, or switch to the Legacy Engine (which uses cloud transcription)."
        } else {
            self.errorMessage = desc
        }
        if isRecording {
            stop()
        }
    }
    
    /// Dynamically loads supported locales for the active engine
    func loadSupportedLocales() async {
        self.supportedLocales = await SpeechLocaleHelper.loadSupportedLocales(for: selectedEngineMode)
    }
    
    /// Resolves the most appropriate locale for the active engine using the fallback hierarchy:
    /// 1. Currently selected locale (if supported)
    /// 2. Device current locale (`Locale.current`, if supported)
    /// 3. English ("en-US" or first available English locale)
    /// 4. First available supported locale
    func resolveLocaleForActiveEngine() {
        let bestIdentifier = SpeechLocaleHelper.resolveLocaleOnEngineSwitch(
            currentSelection: selectedLocaleIdentifier,
            availableLocales: supportedLocales
        )
        if !SpeechLocaleHelper.isEquivalent(bestIdentifier, selectedLocaleIdentifier) {
            SpeechLog.store.info("Engine switched to \(self.selectedEngineMode.shortTitle): adjusted locale from '\(self.selectedLocaleIdentifier)' to '\(bestIdentifier)'")
        }
        setLocale(identifier: bestIdentifier)
    }
}

