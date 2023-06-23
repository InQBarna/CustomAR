//
//  RecognitionViewController.swift
//  AugmentedReality
//
//  Created by Fatima Syed on 27/3/23.
//

import UIKit
import AVFoundation
import Vision
import CoreML

open class RecognitionViewController: ARViewController, UIViewControllerTransitioningDelegate {
    
    // MARK: - Properties
    
    private var detectionOverlay: CALayer! = nil
    private var requests = [VNRequest]()
    private var hasNavigatedToPanoramaView: Bool = false
    private var detectionTimer: Timer?
    private var detectionRestartTimer: Timer?
    public var detectionTime: Double?
    public var detectionInterval: Double?
    public var customARConfig: CustomARConfig?
    private var currentActionIndex: Int?
    public var infoLabel: UILabel?
    public var infoIcon: UIImageView?
    public var infoLabelInitialText: String?
    private let infoContainer = UIView()
    
    // MARK: - Life Cycle
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        restartCaptureSession()
        initialParameters()
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        restartCaptureSession()
        initialParameters()
    }
    
    func initialParameters() {
        hasNavigatedToPanoramaView = false
        resetZoom()
        if detectionOverlay.superlayer == nil {
            rootLayer.addSublayer(detectionOverlay)
        }
        setupView()
    }
    
    func resetDetectionLabel() {
        self.infoLabel?.text = infoLabelInitialText
        infoLabel?.isHidden = true
        infoIcon?.isHidden = true
        infoContainer.isHidden = true
    }
    
    // MARK: - Capture Session
    
    public override func startCaptureSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    public func stopCaptureSession() {
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    private func restartCaptureSession() {
        stopCaptureSession()
        setupAVCapture()
    }
    
    func resetZoom() {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            
            self.previewLayer?.transform = CATransform3DIdentity
            self.previewLayer?.anchorPoint = CGPoint(x: 0.5, y: 0.5) // Reset anchorPoint
            self.previewLayer?.position = CGPoint(x: self.rootLayer.bounds.midX, y: self.rootLayer.bounds.midY) // Reset position
            
            CATransaction.commit()
        }
    }
    
    func setupVision() {
        if let model = customARConfig?.model {
            guard let objectDetectionModel = try? VNCoreMLModel(for: model) else { return }
            
            let objectRecognition = VNCoreMLRequest(model: objectDetectionModel) { [weak self] request, error in
                if let error = error {
                    print("Object detection error: \(error)")
                    return
                }
                
                guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
                
                DispatchQueue.main.async {
                    self?.drawVisionRequestResults(results)
                }
            }
            self.requests = [objectRecognition]
        }
    }
    
    private func setupView() {
        view.addSubview(closeButton)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])

        guard let infoIcon = infoIcon, let infoLabel = infoLabel else { return }

        let infoStackView = UIStackView(arrangedSubviews: [infoIcon, infoLabel])
        infoStackView.axis = .horizontal
        infoStackView.spacing = 10
        
        infoContainer.backgroundColor = UIColor.gray.withAlphaComponent(0.8)
        infoContainer.layer.cornerRadius = 10
        infoContainer.layer.masksToBounds = true
        infoContainer.isHidden = true
        infoContainer.addSubview(infoStackView)

        view.addSubview(infoContainer)
        
        infoContainer.translatesAutoresizingMaskIntoConstraints = false
        infoStackView.translatesAutoresizingMaskIntoConstraints = false
        infoIcon.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            infoContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            infoContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            infoContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            infoContainer.heightAnchor.constraint(equalToConstant: 40),
            
            infoStackView.leadingAnchor.constraint(equalTo: infoContainer.leadingAnchor, constant: 8),
            infoStackView.topAnchor.constraint(equalTo: infoContainer.topAnchor, constant: 8),
            infoStackView.bottomAnchor.constraint(equalTo: infoContainer.bottomAnchor, constant: -8),
            
            infoIcon.widthAnchor.constraint(equalToConstant: 24),
            infoIcon.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    
    func drawVisionRequestResults(_ results: [Any]) {
        detectionOverlay.sublayers = nil
        var remainingTime = detectionTime ?? 2.0
        
        if let objectObservation = results.compactMap({ $0 as? VNRecognizedObjectObservation })
            .filter({ $0.confidence > 0.5 })
            .max(by: { $0.confidence < $1.confidence }) {
            
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
            
            if detectionTimer == nil {
                self.fireHaptic()
                let labelName = objectObservation.labels.first?.identifier
                if let infoLabel = self.infoLabel, infoLabel.isHidden {
                    DispatchQueue.main.async {
                        infoLabel.text = "\(self.infoLabelInitialText ?? "") \(labelName ?? "")"
                        infoLabel.isHidden = false
                        self.infoIcon?.isHidden = false
                        self.infoContainer.isHidden = false
                    }
                }
                detectionTimer = Timer.scheduledTimer(withTimeInterval: remainingTime, repeats: false) { [weak self] _ in
                    self?.detectionOverlay.removeFromSuperlayer()
                    if let labelName = labelName {
                        self?.detectionTimerExpired(objectBounds, identifier: labelName)
                    }
                }
            } else {
                detectionRestartTimer?.invalidate()
            }
            
            detectionRestartTimer = Timer.scheduledTimer(withTimeInterval: detectionInterval ?? 0.5, repeats: false) { [weak self] _ in
                if let remainingTimeInterval = self?.detectionTimer?.fireDate.timeIntervalSince(Date()) {
                    remainingTime = remainingTimeInterval
                }
                self?.detectionTimer?.invalidate()
                self?.detectionTimer = nil
                self?.resetDetectionLabel()
            }
            
            let shapeLayer = self.createRandomDottedRectLayerWithBounds(objectBounds)
            
            detectionOverlay.addSublayer(shapeLayer)
        }
        self.updateLayerGeometry()
    }

    func createRandomDottedRectLayerWithBounds(_ bounds: CGRect, dotRadius: CGFloat = 1.0, density: CGFloat = 0.015) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        let numberOfDots = Int(bounds.width * bounds.height * density)

        let shadowPath = UIBezierPath()
        let actualPath = UIBezierPath()

        for _ in 0..<numberOfDots {
            let x = CGFloat.randomGaussian() * bounds.width/4 + bounds.midX
            let y = CGFloat.randomGaussian() * bounds.height/4 + bounds.midY
            let shadowDotRadius = CGFloat.random(in: 0.5 * dotRadius...1.5 * dotRadius)
            let actualDotRadius = CGFloat.random(in: 0.5 * dotRadius...1.5 * dotRadius)
            
            shadowPath.move(to: CGPoint(x: x, y: y))
            shadowPath.addArc(withCenter: CGPoint(x: x, y: y), radius: shadowDotRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            
            actualPath.move(to: CGPoint(x: x, y: y))
            actualPath.addArc(withCenter: CGPoint(x: x, y: y), radius: actualDotRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        }

        let shadowLayer = CAShapeLayer()
        shadowLayer.path = shadowPath.cgPath
        shadowLayer.fillColor = UIColor.black.cgColor
        shadowLayer.opacity = 0.2
        shapeLayer.addSublayer(shadowLayer)

        let dotLayer = CAShapeLayer()
        dotLayer.path = actualPath.cgPath
        dotLayer.fillColor = UIColor.red.cgColor
        shapeLayer.addSublayer(dotLayer)

        return shapeLayer
    }
    
    func zoomAnimation(duration: TimeInterval, scale: CGFloat, objectBounds: CGRect, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setCompletionBlock {
                completion?()
            }
            
            let newX = objectBounds.midX / self.detectionOverlay!.bounds.width
            let newY = objectBounds.midY / self.detectionOverlay!.bounds.height
            
            self.previewLayer?.anchorPoint = CGPoint(x: newX, y: newY)
            
            let zoom = CABasicAnimation(keyPath: "transform.scale")
            zoom.fromValue = 1.0
            zoom.toValue = scale
            zoom.duration = duration
            
            self.previewLayer?.add(zoom, forKey: nil)
            self.previewLayer?.transform = CATransform3DScale(self.previewLayer!.transform, scale, scale, 1)
            
            CATransaction.commit()
        }
    }
    
    func fireHaptic() {
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .heavy)
        feedbackGenerator.impactOccurred()
    }
    
    func detectionTimerExpired(_ objectBounds: CGRect, identifier: String) {
        resetDetectionLabel()
        if !hasNavigatedToPanoramaView {
            hasNavigatedToPanoramaView = true
            zoomAnimation(duration: 0.8, scale: 6, objectBounds: objectBounds) { [weak self] in
                if let actions = self?.customARConfig?.objectLabelsWithActions[identifier] {
                    self?.currentActionIndex = 0
                    self?.executeCurrentAction(actions: actions)
                }
            }
        }
    }
    
    func executeCurrentAction(actions: [Action]) {
        guard let currentActionIndex = currentActionIndex, currentActionIndex < actions.count else { return }
        
        let action = actions[currentActionIndex]
        
        switch action.type {
        case .panoramaView:
            if let image = action.media as? UIImage {
                self.navigateToPanoramaView(media: image)
            }
        case .videoPlayer:
            if let videoURL = action.media as? URL {
                self.navigateToVideoPlayer(media: videoURL)
            }
        }
        
        if let index = self.currentActionIndex {
            self.currentActionIndex = index + 1
        }
    }
    
    public override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let exifOrientation = exifOrientationFromDeviceOrientation()
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    override func setupAVCapture() {
        super.setupAVCapture()
        
        // setup Vision parts
        setupLayers()
        updateLayerGeometry()
        setupVision()
        
        // start the capture
        startCaptureSession()
    }
    
    func setupLayers() {
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
    }
    
    func updateLayerGeometry() {
        let bounds = rootLayer.bounds
        var scale: CGFloat
        
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1.0
        }
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
        
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
        shapeLayer.cornerRadius = 7
        return shapeLayer
    }
    
    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "close"), for: .normal)
        button.tintColor = .white
        button.layer.cornerRadius = 10
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        return button
    }()
    
    // MARK: Navigation
    func navigateToPanoramaView(media: UIImage) {
        DispatchQueue.main.async {
            let panoramaViewController = PanoramaViewController()
            panoramaViewController.image = media
            panoramaViewController.modalPresentationStyle = .overCurrentContext
            panoramaViewController.transitioningDelegate = self
            self.present(panoramaViewController, animated: true, completion: nil)
        }
    }
    
    func navigateToVideoPlayer(media: URL) {
        // TODO: ADD VIDEO PLAYER
    }
    
    @objc func didTapClose() {
        self.dismiss(animated: true) {
            self.resetDetectionLabel()
        }
    }
}

extension CGFloat {
    static func randomGaussian(mean: CGFloat = 0.0, standardDeviation: CGFloat = 1.0) -> CGFloat {
        let x1 = CGFloat(arc4random()) / CGFloat(UInt32.max)
        let x2 = CGFloat(arc4random()) / CGFloat(UInt32.max)
        
        let z = sqrt(-2.0 * log(x1)) * cos(2.0 * .pi * x2)
        
        return z * standardDeviation + mean
    }
}
