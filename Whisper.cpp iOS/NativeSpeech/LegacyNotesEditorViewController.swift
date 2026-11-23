//
//  LegacyNotesEditorViewController.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 23/11/26.
//

import UIKit
import SwiftUI

/// A simple, production-ready UIKit example demonstrating how to integrate `CompactSpeechBarLegacyView`
/// into an existing legacy `UIViewController` with a `UITextView`.
///
/// Features:
/// - Functions like native Apple Notes: users can type with the keyboard, move the cursor anywhere,
///   and speak to insert or dictate text directly at the cursor.
/// - Can be hosted directly above the keyboard via `inputAccessoryView` or pinned to the screen bottom.
/// - Errors (storage full, permissions, recognizer unavailable) pop up automatically inside the compact bar.
final class LegacyNotesEditorViewController: UIViewController {
    
    // MARK: - UI Elements
    
    let textView: UITextView = {
        let tv = UITextView()
        tv.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        tv.textColor = .label
        tv.backgroundColor = .systemBackground
        tv.text = "Dear Team,\n\nPlease find the project updates below:\n"
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    
    // Retain UIHostingController reference to ensure lifecycle and touch events remain intact
    private var accessoryHostingController: UIHostingController<CompactSpeechBarLegacyView>?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Apple Notes Style Dictation"
        view.backgroundColor = .systemBackground
        
        setupTextView()
        setupSpeechBarAccessory()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Automatically focus text view on launch so keyboard and compact speech bar appear immediately
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
    }
    
    // MARK: - Setup
    
    private func setupTextView() {
        view.addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])
    }
    
    /// Attaches CompactSpeechBarLegacyView directly above the keyboard as an inputAccessoryView
    private func setupSpeechBarAccessory() {
        // Option 1: Automatic Apple Notes behavior (passes textView directly)
        let speechBar = CompactSpeechBarLegacyView(targetTextView: textView)
        
        // Option 2: Alternatively, using closures (as requested by user):
        /*
        let speechBar = CompactSpeechBarLegacyView { [weak self] fullText in
            // Option A: Full text sync
            print("Current speech text: \(fullText)")
        } onAppendDelta: { [weak self] deltaChunk in
            // Option B: Insert directly at current cursor/selection:
            self?.textView.insertText(deltaChunk)
        }
        */
        
        // Wrap in UIHostingController and attach as inputAccessoryView
        let hostingController = UIHostingController(rootView: speechBar)
        self.accessoryHostingController = hostingController
        
        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 56)
        hostingController.view.autoresizingMask = [.flexibleWidth]
        hostingController.didMove(toParent: self)
        
        textView.inputAccessoryView = hostingController.view
    }
}

