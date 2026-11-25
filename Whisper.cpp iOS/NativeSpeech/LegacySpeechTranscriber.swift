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
    private var isFinishing = false
    
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
        
        isFinishing = false
        startRecognitionRequest()
    }

    private func startRecognitionRequest() {
        guard let recognizer = speechRecognizer, !isFinishing else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
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

                let startsNewUtterance = self.isNewUtterance(
                    previous: self.volatileText,
                    incoming: formatted
                )
                if startsNewUtterance {
                    self.appendFinalizedText(self.volatileText)
                }

                if result.isFinal {
                    self.appendFinalizedText(formatted)
                    self.volatileText = ""
                    self.recognitionTask = nil
                    self.recognitionRequest = nil
                    self.startRecognitionRequest()
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

    /// SFSpeech can begin a fresh utterance after a pause without first marking the
    /// preceding partial result final. Detect that reset and commit the old hypothesis.
    private func isNewUtterance(previous: String, incoming: String) -> Bool {
        let oldWords = normalizedWords(previous)
        let newWords = normalizedWords(incoming)
        guard !oldWords.isEmpty, !newWords.isEmpty else { return false }

        // Partial hypotheses can revise their opening words ("summer in" to
        // "somewhere in"). Any meaningful word overlap is evidence that SFSpeech
        // is revising the same utterance, so replace the volatile hypothesis instead
        // of committing the earlier, less accurate wording.
        return Set(oldWords).isDisjoint(with: Set(newWords))
    }

    private func normalizedWords(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map {
            $0.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }.filter { !$0.isEmpty }
    }

    private func appendFinalizedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        finalizedText = finalizedText.isEmpty ? trimmed : finalizedText + " " + trimmed
    }
    
    /// Streams audio buffer directly to SFSpeechAudioBufferRecognitionRequest with zero conversion overhead
    public func streamAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let request = recognitionRequest else {
            throw LegacyTranscriptionError.recognitionRequestFailed("No active recognition session.")
        }
        request.append(buffer)
    }
    
    public func finishTranscribing() async throws {
        isFinishing = true
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

    public func setInitialTranscript(_ text: String) {
        finalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
