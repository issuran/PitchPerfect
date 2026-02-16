////
////  PlaySoundsViewController.swift
////  PitchPerfect
////
////  Created by Tiago Oliveira on 01/01/18.
////  Copyright © 2018 Tiago Oliveira. All rights reserved.
////

import UIKit
import AVFoundation

class PlaySoundsViewController: UIViewController {
    
    @IBOutlet weak var snailButton: UIButton!
    @IBOutlet weak var chipmunkButton: UIButton!
    @IBOutlet weak var rabbitButton: UIButton!
    @IBOutlet weak var vaderButton: UIButton!
    @IBOutlet weak var echoButton: UIButton!
    @IBOutlet weak var reverbButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!
    @IBOutlet weak var shareButton: UIButton! // ADD THIS TO YOUR STORYBOARD
    
    var recordedAudioURL: URL!
    var audioFile: AVAudioFile!
    var audioEngine: AVAudioEngine!
    var audioPlayerNode: AVAudioPlayerNode!
    var stopTimer: Timer!
    
    // Loading indicator
    var loadingView: UIView?
    var activityIndicator: UIActivityIndicatorView?
    
    // Track selected effect
    var selectedEffect: ButtonType?
    var processedAudioURL: URL?
    
    enum ButtonType: Int {
        case slow = 0, fast, chipmunk, vader, echo, reverb
    }
    
    @IBAction func playSoundForButton(_ sender: UIButton) {
        let buttonType = ButtonType(rawValue: sender.tag)!
        
        // Update selected effect
        selectedEffect = buttonType
        updateButtonSelection(selectedButton: sender)
        
        // Play sound with effect
        switch(buttonType) {
        case .slow:
            playSound(rate: 0.5)
        case .fast:
            playSound(rate: 1.5)
        case .chipmunk:
            playSound(pitch: 1000)
        case .vader:
            playSound(pitch: -1000)
        case .echo:
            playSound(echo: true)
        case .reverb:
            playSound(reverb: true)
        }
        
        configureUI(.playing)
        
        // Show share button when effect is selected
        shareButton.isHidden = false
    }
    
    @IBAction func stopButtonPressed(_ sender: AnyObject){
        stopAudio()
    }
    
    @IBAction func shareButtonPressed(_ sender: UIButton) {
        guard let selectedEffect = selectedEffect else {
            showAlert("No Effect Selected", message: "Please select an effect first")
            return
        }
        
        // Stop any playing audio first - CRITICAL FIX
        if let playerNode = audioPlayerNode {
            playerNode.stop()
        }
        if let engine = audioEngine {
            engine.stop()
            engine.reset()
        }
        if let timer = stopTimer {
            timer.invalidate()
        }
        
        // Show loading indicator
        showLoadingIndicator(message: "Preparing audio...")
        
        // Export audio with effect, then share
        exportAudioWithEffect(selectedEffect) { [weak self] exportedURL in
            guard let self = self else { return }
            
            // ALWAYS hide loading indicator on main thread
            DispatchQueue.main.async {
                self.hideLoadingIndicator()
                
                guard let url = exportedURL else {
                    self.showAlert("Export Failed", message: "Could not export audio file")
                    return
                }
                
                self.shareToWhatsApp(audioURL: url)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupAudio()
        shareButton.isHidden = true // Hide until effect is selected
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureUI(.notPlaying)
        selectedEffect = nil
        shareButton.isHidden = true
        resetButtonSelection()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // MARK: - Visual Feedback for Selected Effect
    
    func updateButtonSelection(selectedButton: UIButton) {
        // Reset all buttons
        let allButtons = [snailButton, chipmunkButton, rabbitButton, vaderButton, echoButton, reverbButton]
        allButtons.forEach { button in
            button?.alpha = 0.5
            button?.layer.borderWidth = 0
        }
        
        // Highlight selected button
        selectedButton.alpha = 1.0
        selectedButton.layer.borderWidth = 3
        selectedButton.layer.borderColor = UIColor.systemBlue.cgColor
        selectedButton.layer.cornerRadius = 8
    }
    
    func resetButtonSelection() {
        let allButtons = [snailButton, chipmunkButton, rabbitButton, vaderButton, echoButton, reverbButton]
        allButtons.forEach { button in
            button?.alpha = 1.0
            button?.layer.borderWidth = 0
        }
    }
    
    // MARK: - Export Audio with Effect (OFFLINE PROCESSING - NO PLAYBACK)
    
    func exportAudioWithEffect(_ effect: ButtonType, completion: @escaping (URL?) -> Void) {
        // Process in background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            // Create output file URL
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let outputURL = documentsPath.appendingPathComponent("processedAudio_\(Date().timeIntervalSince1970).m4a")
            
            // Remove existing file if it exists
            try? FileManager.default.removeItem(at: outputURL)
            
            do {
                // Load source audio file
                let sourceFile = try AVAudioFile(forReading: self.recordedAudioURL)
                let sourceFormat = sourceFile.processingFormat
                
                // Create audio engine for offline processing
                let engine = AVAudioEngine()
                let player = AVAudioPlayerNode()
                engine.attach(player)
                
                // Create effect node based on selection
                switch effect {
                case .slow, .fast:
                    let pitchNode = AVAudioUnitTimePitch()
                    pitchNode.rate = (effect == .slow) ? 0.5 : 1.5
                    engine.attach(pitchNode)
                    engine.connect(player, to: pitchNode, format: sourceFormat)
                    engine.connect(pitchNode, to: engine.mainMixerNode, format: sourceFormat)
                    
                case .chipmunk, .vader:
                    let pitchNode = AVAudioUnitTimePitch()
                    pitchNode.pitch = (effect == .chipmunk) ? 1000 : -1000
                    engine.attach(pitchNode)
                    engine.connect(player, to: pitchNode, format: sourceFormat)
                    engine.connect(pitchNode, to: engine.mainMixerNode, format: sourceFormat)
                    
                case .echo:
                    let echoNode = AVAudioUnitDistortion()
                    echoNode.loadFactoryPreset(.multiEcho1)
                    engine.attach(echoNode)
                    engine.connect(player, to: echoNode, format: sourceFormat)
                    engine.connect(echoNode, to: engine.mainMixerNode, format: sourceFormat)
                    
                case .reverb:
                    let reverbNode = AVAudioUnitReverb()
                    reverbNode.loadFactoryPreset(.cathedral)
                    reverbNode.wetDryMix = 50
                    engine.attach(reverbNode)
                    engine.connect(player, to: reverbNode, format: sourceFormat)
                    engine.connect(reverbNode, to: engine.mainMixerNode, format: sourceFormat)
                }
                
                // Prepare output file
                let outputSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sourceFormat.sampleRate,
                    AVNumberOfChannelsKey: sourceFormat.channelCount,
                    AVEncoderBitRateKey: 128000
                ]
                let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
                
                // Set up offline rendering
                let maxFrames: AVAudioFrameCount = 4096
                try engine.enableManualRenderingMode(.offline, format: sourceFormat, maximumFrameCount: maxFrames)
                
                try engine.start()
                
                // Schedule the source audio
                player.scheduleFile(sourceFile, at: nil)
                player.play()
                
                // Create buffer for rendering
                guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
                    throw NSError(domain: "AudioExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
                }
                
                // Render audio offline (NO PLAYBACK TO SPEAKERS)
                while engine.manualRenderingSampleTime < sourceFile.length {
                    let framesToRender = min(buffer.frameCapacity, AVAudioFrameCount(sourceFile.length - engine.manualRenderingSampleTime))
                    let status = try engine.renderOffline(framesToRender, to: buffer)
                    
                    switch status {
                    case .success:
                        try outputFile.write(from: buffer)
                    case .insufficientDataFromInputNode:
                        break
                    case .cannotDoInCurrentContext:
                        break
                    case .error:
                        throw NSError(domain: "AudioExport", code: -2, userInfo: [NSLocalizedDescriptionKey: "Rendering error"])
                    @unknown default:
                        break
                    }
                }
                
                // Stop engine
                player.stop()
                engine.stop()
                
                // Success - call completion on main thread
                DispatchQueue.main.async {
                    completion(outputURL)
                }
                
            } catch {
                print("Export error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - WhatsApp Sharing
    
    func shareToWhatsApp(audioURL: URL) {
        // Check if WhatsApp is installed
        let whatsappURL = URL(string: "whatsapp://")!
        
        if UIApplication.shared.canOpenURL(whatsappURL) {
            // Use UIActivityViewController (works for WhatsApp and other apps)
            let activityVC = UIActivityViewController(activityItems: [audioURL], applicationActivities: nil)
            
            // Exclude some activities if desired
            activityVC.excludedActivityTypes = [
                .addToReadingList,
                .assignToContact,
                .print
            ]
            
            // CRITICAL FIX: Add completion handler to detect when share sheet is dismissed
            activityVC.completionWithItemsHandler = { [weak self] (activityType, completed, returnedItems, error) in
                // This is called when user dismisses the share sheet
                // Make sure loading is hidden
                DispatchQueue.main.async {
                    self?.hideLoadingIndicator()
                }
            }
            
            // For iPad - prevent crash
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = shareButton
                popover.sourceRect = shareButton.bounds
            }
            
            present(activityVC, animated: true) {
                // This is called when the share sheet appears
                // Loading should already be hidden at this point
            }
        } else {
            // WhatsApp not installed
            hideLoadingIndicator() // Make sure to hide loading here too
            showAlert("WhatsApp Not Found", message: "Please install WhatsApp to share audio")
        }
    }
    
    // MARK: - Loading Indicator
    
    func showLoadingIndicator(message: String) {
        // Create semi-transparent background
        let loadingView = UIView(frame: view.bounds)
        loadingView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        loadingView.tag = 999 // Tag for easy removal
        
        // Create container for spinner and text
        let containerView = UIView()
        containerView.backgroundColor = UIColor.darkGray
        containerView.layer.cornerRadius = 12
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create activity indicator
        let activityIndicator: UIActivityIndicatorView
        if #available(iOS 13.0, *) {
            activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .large)
        } else {
            activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
        }
        activityIndicator.color = .white
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.startAnimating()
        
        // Create label
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews
        containerView.addSubview(activityIndicator)
        containerView.addSubview(label)
        loadingView.addSubview(containerView)
        view.addSubview(loadingView)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor),
            containerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            containerView.heightAnchor.constraint(equalToConstant: 100),
            
            activityIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            
            label.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            label.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 12),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -20)
        ])
        
        self.loadingView = loadingView
        self.activityIndicator = activityIndicator
    }
    
    func hideLoadingIndicator() {
        if let loadingView = view.viewWithTag(999) {
            UIView.animate(withDuration: 0.3, animations: {
                loadingView.alpha = 0
            }) { _ in
                loadingView.removeFromSuperview()
            }
        }
        self.loadingView = nil
        self.activityIndicator = nil
    }
}

//
//import UIKit
//import AVFoundation
//
//class PlaySoundsViewController: UIViewController {
//    
//    @IBOutlet weak var snailButton: UIButton!
//    @IBOutlet weak var chipmunkButton: UIButton!
//    @IBOutlet weak var rabbitButton: UIButton!
//    @IBOutlet weak var vaderButton: UIButton!
//    @IBOutlet weak var echoButton: UIButton!
//    @IBOutlet weak var reverbButton: UIButton!
//    @IBOutlet weak var stopButton: UIButton!
//    @IBOutlet weak var shareButton: UIButton! // ADD THIS TO YOUR STORYBOARD
//    
//    var recordedAudioURL: URL!
//    var audioFile: AVAudioFile!
//    var audioEngine: AVAudioEngine!
//    var audioPlayerNode: AVAudioPlayerNode!
//    var stopTimer: Timer!
//    
//    // Loading indicator
//    var loadingView: UIView?
//    var activityIndicator: UIActivityIndicatorView?
//    
//    // Track selected effect
//    var selectedEffect: ButtonType?
//    var processedAudioURL: URL?
//    
//    enum ButtonType: Int {
//        case slow = 0, fast, chipmunk, vader, echo, reverb
//    }
//    
//    @IBAction func playSoundForButton(_ sender: UIButton) {
//        let buttonType = ButtonType(rawValue: sender.tag)!
//        
//        // Update selected effect
//        selectedEffect = buttonType
//        updateButtonSelection(selectedButton: sender)
//        
//        // Play sound with effect
//        switch(buttonType) {
//        case .slow:
//            playSound(rate: 0.5)
//        case .fast:
//            playSound(rate: 1.5)
//        case .chipmunk:
//            playSound(pitch: 1000)
//        case .vader:
//            playSound(pitch: -1000)
//        case .echo:
//            playSound(echo: true)
//        case .reverb:
//            playSound(reverb: true)
//        }
//        
//        configureUI(.playing)
//        
//        // Show share button when effect is selected
//        shareButton.isHidden = false
//    }
//    
//    @IBAction func stopButtonPressed(_ sender: AnyObject){
//        stopAudio()
//    }
//    
//    @IBAction func shareButtonPressed(_ sender: UIButton) {
//        guard let selectedEffect = selectedEffect else {
//            showAlert("No Effect Selected", message: "Please select an effect first")
//            return
//        }
//        
//        // Stop any playing audio first
////        stopAudio()
//        if let playerNode = audioPlayerNode {
//            playerNode.stop()
//        }
//        if let engine = audioEngine {
//            engine.stop()
//            engine.reset()
//        }
//        if let timer = stopTimer {
//            timer.invalidate()
//        }
//        
//        // Show loading indicator
//        showLoadingIndicator(message: "Preparing audio...")
//        
//        // Export audio with effect, then share
//        exportAudioWithEffect(selectedEffect) { [weak self] exportedURL in
//            guard let self = self, let url = exportedURL else {
//                self?.showAlert("Export Failed", message: "Could not export audio file")
//                return
//            }
//            
//            self.shareToWhatsApp(audioURL: url)
//        }
//    }
//
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        setupAudio()
//        shareButton.isHidden = true // Hide until effect is selected
//    }
//    
//    override func viewWillAppear(_ animated: Bool) {
//        super.viewWillAppear(animated)
//        configureUI(.notPlaying)
//        selectedEffect = nil
//        shareButton.isHidden = true
//        resetButtonSelection()
//    }
//
//    override func didReceiveMemoryWarning() {
//        super.didReceiveMemoryWarning()
//    }
//    
//    // MARK: - Visual Feedback for Selected Effect
//    
//    func updateButtonSelection(selectedButton: UIButton) {
//        // Reset all buttons
//        let allButtons = [snailButton, chipmunkButton, rabbitButton, vaderButton, echoButton, reverbButton]
//        allButtons.forEach { button in
//            button?.alpha = 0.5
//            button?.layer.borderWidth = 0
//        }
//        
//        // Highlight selected button
//        selectedButton.alpha = 1.0
//        selectedButton.layer.borderWidth = 3
//        selectedButton.layer.borderColor = UIColor.systemBlue.cgColor
//        selectedButton.layer.cornerRadius = 8
//    }
//    
//    func resetButtonSelection() {
//        let allButtons = [snailButton, chipmunkButton, rabbitButton, vaderButton, echoButton, reverbButton]
//        allButtons.forEach { button in
//            button?.alpha = 1.0
//            button?.layer.borderWidth = 0
//        }
//    }
//    
//    // MARK: - Export Audio with Effect
//    
//    func exportAudioWithEffect(_ effect: ButtonType, completion: @escaping (URL?) -> Void) {
//        // Stop any playing audio first
//        stopAudio()
//        
//        // Create output file URL
//        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//        let outputURL = documentsPath.appendingPathComponent("processedAudio_\(Date().timeIntervalSince1970).m4a")
//        
//        // Remove existing file if it exists
//        try? FileManager.default.removeItem(at: outputURL)
//        
//        do {
//            // Setup audio engine
//            let engine = AVAudioEngine()
//            let playerNode = AVAudioPlayerNode()
//            engine.attach(playerNode)
//            
//            // Load audio file
//            let audioFile = try AVAudioFile(forReading: recordedAudioURL)
//            
//            // Create effect node based on selection
//            let effectNode: AVAudioNode
//            
//            switch effect {
//            case .slow, .fast:
//                let pitchNode = AVAudioUnitTimePitch()
//                pitchNode.rate = (effect == .slow) ? 0.5 : 1.5
//                engine.attach(pitchNode)
//                effectNode = pitchNode
//                
//            case .chipmunk, .vader:
//                let pitchNode = AVAudioUnitTimePitch()
//                pitchNode.pitch = (effect == .chipmunk) ? 1000 : -1000
//                engine.attach(pitchNode)
//                effectNode = pitchNode
//                
//            case .echo:
//                let echoNode = AVAudioUnitDistortion()
//                echoNode.loadFactoryPreset(.multiEcho1)
//                engine.attach(echoNode)
//                effectNode = echoNode
//                
//            case .reverb:
//                let reverbNode = AVAudioUnitReverb()
//                reverbNode.loadFactoryPreset(.cathedral)
//                reverbNode.wetDryMix = 50
//                engine.attach(reverbNode)
//                effectNode = reverbNode
//            }
//            
//            // Connect nodes
//            engine.connect(playerNode, to: effectNode, format: audioFile.processingFormat)
//            engine.connect(effectNode, to: engine.mainMixerNode, format: audioFile.processingFormat)
//            
//            // Setup output file
//            let outputFile = try AVAudioFile(forWriting: outputURL, settings: audioFile.fileFormat.settings)
//            
//            // Install tap to write processed audio
//            engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: audioFile.processingFormat) { buffer, time in
//                do {
//                    try outputFile.write(from: buffer)
//                } catch {
//                    print("Error writing buffer: \(error)")
//                }
//            }
//            
//            // Schedule file and start engine
//            playerNode.scheduleFile(audioFile, at: nil) {
//                // Stop engine after playback completes
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                    engine.mainMixerNode.removeTap(onBus: 0)
//                    engine.stop()
//                    playerNode.stop()
//                    completion(outputURL)
//                }
//            }
//            
//            try engine.start()
//            playerNode.play()
//            
//        } catch {
//            print("Export error: \(error)")
//            completion(nil)
//        }
//    }
//    
//    // MARK: - WhatsApp Sharing
//    
//    func shareToWhatsApp(audioURL: URL) {
//        // Check if WhatsApp is installed
//        let whatsappURL = URL(string: "whatsapp://")!
//        
//        if UIApplication.shared.canOpenURL(whatsappURL) {
//            // Use UIActivityViewController (works for WhatsApp and other apps)
//            let activityVC = UIActivityViewController(activityItems: [audioURL], applicationActivities: nil)
//            
//            activityVC.completionWithItemsHandler = { [weak self] (activityType, completed, returnedItems, error) in
//                // Called when user dismisses share sheet
//                DispatchQueue.main.async {
//                    self?.hideLoadingIndicator() // ✅ ALWAYS hide loading
//                }
//            }
//            
//            // Exclude some activities if desired
//            activityVC.excludedActivityTypes = [
//                .addToReadingList,
//                .assignToContact,
//                .print
//            ]
//            
//            // For iPad - prevent crash
//            if let popover = activityVC.popoverPresentationController {
//                popover.sourceView = shareButton
//                popover.sourceRect = shareButton.bounds
//            }
//            
//            present(activityVC, animated: true)
//        } else {
//            // WhatsApp not installed
//            showAlert("WhatsApp Not Found", message: "Please install WhatsApp to share audio")
//            DispatchQueue.main.async {
//                self.hideLoadingIndicator() // ✅ ALWAYS hide loading
//            }
//        }
//    }
//    
//    // MARK: - Loading Indicator
//    
//    func showLoadingIndicator(message: String) {
//        // Create semi-transparent background
//        let loadingView = UIView(frame: view.bounds)
//        loadingView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
//        loadingView.tag = 999 // Tag for easy removal
//        
//        // Create container for spinner and text
//        let containerView = UIView()
//        containerView.backgroundColor = UIColor.darkGray
//        containerView.layer.cornerRadius = 12
//        containerView.translatesAutoresizingMaskIntoConstraints = false
//        
//        // Create activity indicator
//        let activityIndicator: UIActivityIndicatorView
//        if #available(iOS 13.0, *) {
//            activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .large)
//        } else {
//            activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
//        }
//        activityIndicator.color = .white
//        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
//        activityIndicator.startAnimating()
//        
//        // Create label
//        let label = UILabel()
//        label.text = message
//        label.textColor = .white
//        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)
//        label.translatesAutoresizingMaskIntoConstraints = false
//        
//        // Add subviews
//        containerView.addSubview(activityIndicator)
//        containerView.addSubview(label)
//        loadingView.addSubview(containerView)
//        view.addSubview(loadingView)
//        
//        // Layout constraints
//        NSLayoutConstraint.activate([
//            containerView.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
//            containerView.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor),
//            containerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
//            containerView.heightAnchor.constraint(equalToConstant: 100),
//            
//            activityIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
//            activityIndicator.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
//            
//            label.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
//            label.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 12),
//            label.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor, constant: 20),
//            label.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor, constant: -20)
//        ])
//        
//        self.loadingView = loadingView
//        self.activityIndicator = activityIndicator
//    }
//    
//    func hideLoadingIndicator() {
//        if let loadingView = view.viewWithTag(999) {
//            UIView.animate(withDuration: 0.3, animations: {
//                loadingView.alpha = 0
//            }) { _ in
//                loadingView.removeFromSuperview()
//            }
//        }
//        self.loadingView = nil
//        self.activityIndicator = nil
//    }
//}
////import UIKit
////import AVFoundation
////
////class PlaySoundsViewController: UIViewController {
////    
////    @IBOutlet weak var snailButton: UIButton!
////    @IBOutlet weak var chipmunkButton: UIButton!
////    @IBOutlet weak var rabbitButton: UIButton!
////    @IBOutlet weak var vaderButton: UIButton!
////    @IBOutlet weak var echoButton: UIButton!
////    @IBOutlet weak var reverbButton: UIButton!
////    @IBOutlet weak var stopButton: UIButton!
////    @IBOutlet weak var shareButton: UIButton!
////    
////    var recordedAudioURL: URL!
////    var audioFile:AVAudioFile!
////    var audioEngine:AVAudioEngine!
////    var audioPlayerNode: AVAudioPlayerNode!
////    var stopTimer: Timer!
////    
////    enum ButtonType: Int {
////        case slow = 0, fast, chipmunk, vader, echo, reverb
////    }
////    
////    @IBAction func playSoundForButton(_ sender: UIButton) {
////        switch(ButtonType(rawValue: sender.tag)!) {
////        case .slow:
////            playSound(rate: 0.5)
////        case .fast:
////            playSound(rate: 1.5)
////        case .chipmunk:
////            playSound(pitch: 1000)
////        case .vader:
////            playSound(pitch: -1000)
////        case .echo:
////            playSound(echo: true)
////        case .reverb:
////            playSound(reverb: true)
////        }
////        
////        configureUI(.playing)
////    }
////    
////    @IBAction func stopButtonPressed(_ sender: AnyObject){
////        stopAudio()
////    }
////    
////    @IBAction func shareButtonPressed(_ sender: Any) {
////    }
////
////    override func viewDidLoad() {
////        super.viewDidLoad()
////        setupAudio()
////        // Do any additional setup after loading the view.
////    }
////    
////    override func viewWillAppear(_ animated: Bool) {
////        super.viewWillAppear(animated)
////        configureUI(.notPlaying)
////    }
////
////    override func didReceiveMemoryWarning() {
////        super.didReceiveMemoryWarning()
////        // Dispose of any resources that can be recreated.
////    }
////    
////
////    /*
////    // MARK: - Navigation
////
////    // In a storyboard-based application, you will often want to do a little preparation before navigation
////    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
////        // Get the new view controller using segue.destinationViewController.
////        // Pass the selected object to the new view controller.
////    }
////    */
////
////}
