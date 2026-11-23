//
//  LegacySpeechTranscriber.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 12/11/26.
//

import AVFoundation
import Foundation
import Speech

public enum LegacyTranscriptionError: LocalizedError {
    case speechRecognitionUnauthorized
    case recognizerUnavailable
    case recognitionRequestFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .speechRecognitionUnauthorized:
            return "Speech recognition permission is not authorized. Please enable it in Settings."
        case .recognizerUnavailable:
            return "Speech recognizer is currently unavailable for the chosen language."
        case .recognitionRequestFailed(let reason):
            return "Speech recognition failed: \(reason)"
        }
    }
}

@MainActor
public final class LegacySpeechTranscriber: SpeechTranscriptionService {
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // States for Store sync
    public var finalizedText: String = ""
    public var volatileText: String = ""
    public var tokens: [SpeechTranscriptionToken] = []
    public var downloadProgress: Progress? = nil
    public var isDownloadingModel: Bool = false
    public var onError: (@Sendable (Error) -> Void)? = nil
    public var onTranscriptUpdate: (@Sendable () -> Void)? = nil
    
    public var engineDescription: String {
        "Apple SFSpeechRecognizer (iOS 16+)"
    }
    
    public var fullTranscript: String {
        let first = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        return first + " " + second
    }
    
    public init() {}
    
    public func setUpTranscriber(locale: Locale) async throws {
        // 1. Check authorization status
        let authStatus = await requestSpeechAuthorization()
        guard authStatus == .authorized else {
            throw LegacyTranscriptionError.speechRecognitionUnauthorized
        }
        
        // 2. Resolve matching locale
        let availableLocales = Array(SFSpeechRecognizer.supportedLocales())
        let availableIDs = availableLocales.map { $0.identifier }
        let resolvedID = SpeechLocaleHelper.findBestMatchingLocale(
            for: locale.identifier,
            in: availableIDs
        )
        let targetLocale = Locale(identifier: resolvedID)
        
        guard let recognizer = SFSpeechRecognizer(locale: targetLocale), recognizer.isAvailable else {
            throw LegacyTranscriptionError.recognizerUnavailable
        }
        self.speechRecognizer = recognizer
        
        // 3. Configure audio buffer request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        // Attempt on-device recognition if available for speed and privacy
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            request.requiresOnDeviceRecognition = false
        }
        self.recognitionRequest = request
        
        // 4. Start recognition task
        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            
            if let result {
                let formatted = result.bestTranscription.formattedString
                let segmentTokens = result.bestTranscription.segments.map { seg in
                    SpeechTranscriptionToken(
                        text: seg.substring,
                        confidence: seg.confidence,
                        timestamp: seg.timestamp,
                        duration: seg.duration
                    )
                }
                self.tokens = segmentTokens
                
                if result.isFinal {
                    let trimmed = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        if self.finalizedText.isEmpty {
                            self.finalizedText = trimmed
                        } else {
                            self.finalizedText += " " + trimmed
                        }
                    }
                    self.volatileText = ""
                } else {
                    self.volatileText = formatted
                }
                
                self.onTranscriptUpdate?()
            }
            
            if let error {
                SpeechLog.legacy.debug("SFSpeechRecognizer task notification: \(error.localizedDescription)")
                self.onError?(error)
            }
        }
    }
    
    /// Streams audio buffer directly to SFSpeechAudioBufferRecognitionRequest with zero conversion overhead
    public func streamAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let request = recognitionRequest else {
            throw LegacyTranscriptionError.recognitionRequestFailed("No active recognition session.")
        }
        request.append(buffer)
    }
    
    public func finishTranscribing() async throws {
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Allow in-flight partial results to settle
        try? await Task.sleep(nanoseconds: 150_000_000)
        
        recognitionTask?.finish()
        recognitionTask = nil
    }
    
    public func clear() {
        finalizedText = ""
        volatileText = ""
        tokens = []
        onTranscriptUpdate?()
    }
    
    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
