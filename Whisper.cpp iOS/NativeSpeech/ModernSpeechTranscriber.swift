//
//  ModernSpeechTranscriber.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 12/11/26.
//

import AVFoundation
import Foundation
import Speech

@available(iOS 26.0, macOS 26.0, *)
public enum ModernTranscriptionError: LocalizedError {
    case couldNotDownloadModel
    case failedToSetupRecognitionStream
    case invalidAudioDataType
    case localeNotSupported
    case insufficientStorage(String)
    case recognitionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .couldNotDownloadModel:
            return "Could not download the speech model for the selected language."
        case .failedToSetupRecognitionStream:
            return "Could not set up the speech recognition stream."
        case .invalidAudioDataType:
            return "Unsupported audio format for SpeechAnalyzer."
        case .localeNotSupported:
            return "This language/locale is not supported on-device by SpeechAnalyzer."
        case .insufficientStorage(let detail):
            return "Device Storage Full: On-device speech recognition requires free disk space to compile neural models (\(detail)). Please free up storage in iPhone Settings, or switch to the Legacy Engine (cloud)."
        case .recognitionFailed(let reason):
            if reason.localizedCaseInsensitiveContains("No space left on device") || reason.contains("201") {
                return "Device Storage Full: On-device speech recognition requires free disk space to compile neural models. Please free up storage in iPhone Settings, or switch to the Legacy Engine (cloud)."
            }
            return "Speech recognition failed: \(reason)"
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
public final class ModernSpeechTranscriber: SpeechTranscriptionService {
    
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var recognizerTask: Task<Void, Never>?
    
    private let converter = NativeBufferConverter()
    private var analyzerFormat: AVAudioFormat?
    
    // States for Store sync
    public var finalizedText: String = ""
    public var volatileText: String = ""
    public var tokens: [SpeechTranscriptionToken] = []
    public var downloadProgress: Progress? = nil
    public var isDownloadingModel: Bool = false
    public var onError: (@Sendable (Error) -> Void)? = nil
    public var onTranscriptUpdate: (@Sendable () -> Void)? = nil
    
    public var engineDescription: String {
        "Apple SpeechAnalyzer (iOS 26+)"
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
        // 0. Clean temporary directory of lingering cache files
        clearAppTemporaryDirectory()
        
        // 1. Resolve matching locale among supported
        let supported = await SpeechTranscriber.supportedLocales
        let supportedIDs = supported.map { $0.identifier(.bcp47) }
        let resolvedID = SpeechLocaleHelper.findBestMatchingLocale(
            for: locale.identifier(.bcp47),
            in: supportedIDs
        )
        let targetLocale = Locale(identifier: resolvedID)
        
        // 2. Release previously reserved/allocated locales (e.g. es_US) so slots are clean
        await releaseAllReservedLocales()
        
        // 3. Allocate and reserve targetLocale with AssetInventory
        do {
            _ = try await AssetInventory.reserve(locale: targetLocale)
            SpeechLog.modern.info("Reserved locale in AssetInventory: \(targetLocale.identifier(.bcp47))")
        } catch {
            SpeechLog.modern.error("AssetInventory.reserve failed: \(error.localizedDescription)")
            if error.localizedDescription.localizedCaseInsensitiveContains("No space left on device") {
                throw ModernTranscriptionError.insufficientStorage(targetLocale.identifier(.bcp47))
            }
        }
        
        // 4. Ensure model is installed, or download it if needed
        try await ensureModel(locale: targetLocale)
        
        // 5. Instantiate transcriber and analyzer with the now-allocated locale
        let transcriber = SpeechTranscriber(
            locale: targetLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber
        
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        
        self.analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        
        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputSequence = stream
        self.inputBuilder = builder
        
        recognizerTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { break }
                    let text = String(result.text.characters)
                    
                    // Extract tokens from words
                    let words = text.split(separator: " ").map { String($0) }
                    self.tokens = words.map { SpeechTranscriptionToken(text: $0) }
                    
                    if result.isFinal {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            if self.finalizedText.isEmpty {
                                self.finalizedText = trimmed
                            } else {
                                self.finalizedText += " " + trimmed
                            }
                        }
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }
                    
                    self.onTranscriptUpdate?()
                }
            } catch {
                SpeechLog.modern.error("SpeechAnalyzer recognition stream error: \(error.localizedDescription)")
                let desc = error.localizedDescription
                let isNoSpace = desc.localizedCaseInsensitiveContains("No space left on device")
                    || (error as NSError).domain == "EARErrorDomain" && (error as NSError).code == 201
                let reported: Error = isNoSpace
                    ? ModernTranscriptionError.insufficientStorage(targetLocale.identifier(.bcp47))
                    : error
                self?.onError?(reported)
            }
        }
        
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            let desc = error.localizedDescription
            if desc.localizedCaseInsensitiveContains("No space left on device")
                || (error as NSError).domain == "EARErrorDomain" && (error as NSError).code == 201 {
                throw ModernTranscriptionError.insufficientStorage(targetLocale.identifier(.bcp47))
            }
            throw error
        }
    }
    
    public func streamAudioBuffer(_ buffer: AVAudioPCMBuffer) throws {
        guard let inputBuilder, let analyzerFormat else {
            throw ModernTranscriptionError.invalidAudioDataType
        }
        
        let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
        let input = AnalyzerInput(buffer: converted)
        inputBuilder.yield(input)
    }
    
    public func finishTranscribing() async throws {
        inputBuilder?.finish()
        inputBuilder = nil
        inputSequence = nil
        
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        recognizerTask?.cancel()
        recognizerTask = nil
        converter.reset()
        
        self.analyzer = nil
        self.transcriber = nil
        
        // Release locale reservations to prevent holding allocation slots
        await releaseAllReservedLocales()
    }
    
    public func clear() {
        finalizedText = ""
        volatileText = ""
        tokens = []
        onTranscriptUpdate?()
    }
    
    // MARK: - Model Availability & Download
    
    private func ensureModel(locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw ModernTranscriptionError.localeNotSupported
        }
        
        if await installed(locale: locale) {
            return
        }
        
        try await downloadIfNeeded(locale: locale)
    }
    
    private func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }
    
    private func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }
    
    private func downloadIfNeeded(locale: Locale) async throws {
        isDownloadingModel = true
        onTranscriptUpdate?()
        defer {
            isDownloadingModel = false
            onTranscriptUpdate?()
        }
        
        let dummyModule = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [dummyModule]) {
            self.downloadProgress = downloader.progress
            try await downloader.downloadAndInstall()
        }
    }
    
    private func releaseAllReservedLocales() async {
        let reserved = await AssetInventory.reservedLocales
        for loc in reserved {
            await AssetInventory.release(reservedLocale: loc)
        }
    }
    
    private func clearAppTemporaryDirectory() {
        let fileManager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        if let items = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) {
            for item in items {
                try? fileManager.removeItem(at: item)
            }
        }
        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let speechCache = cacheDir.appendingPathComponent("SpeechModelCache")
            try? fileManager.removeItem(at: speechCache)
        }
    }
}
