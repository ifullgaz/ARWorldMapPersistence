/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import ARKit
import ARObject
import ARWorldMapPersistence
import IFGExtensions

private extension ARSCNView {
    /// Center of the view
    var screenCenter: CGPoint {
        let bounds = self.bounds
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
}

class ViewController: ARObjectViewController {
    // MARK: - IBOutlets
    
    @IBOutlet weak var saveExperienceButton: UIButton!
    @IBOutlet weak var loadExperienceButton: UIButton!
    @IBOutlet weak var snapshotThumbnail: UIImageView!
    
    var arObject: ARObject = {
        guard let sceneURL = Bundle.main.url(forResource: "cup", withExtension: "scn", subdirectory: "Assets.scnassets/cup"),
            let referenceNode = ARObject(url: sceneURL) else {
                fatalError("can't load virtual object")
        }
        referenceNode.allowedAlignment = .horizontal
        return referenceNode
    }()

    let worldMapArchiver: ARWorldMapFileArchiver = ARWorldMapFileArchiver(fileName: "map")
    
    var isRelocalizingMap = false

    var worldMap: ARWorldMap?
    
    // MARK: - Private interface
    private func updateSessionInfoLabel(for frame: ARFrame, trackingState: ARCamera.TrackingState) {
        // Update the UI to provide feedback on the state of the AR experience.
        let message: String
        
        snapshotThumbnail.isHidden = true
        switch (trackingState, frame.worldMappingStatus) {
        case (.normal, .mapped),
             (.normal, .extending):
            if frame.anchors.contains(where: { $0.name == arObject.name }) {
                // User has placed an object in scene and the session is mapped, prompt them to save the experience
                message = "Tap 'Save Experience' to save the current map."
            } else {
                message = "Tap on the screen to place an object."
            }
            
        case (.normal, _) where worldMapArchiver.fileExists() && self.worldMap == nil:
            message = "Move around to map the environment or tap 'Load Experience' to load a saved experience."
            
        case (.normal, _) where !worldMapArchiver.fileExists():
            message = "Move around to map the environment."
            
        case (.limited(.relocalizing), _) where self.worldMap != nil:
            message = "Move your device to the location shown in the image."
            snapshotThumbnail.isHidden = false
            
        default:
            message = trackingState.feedback
        }

        self.sceneView.statusView?.present(message: message)
    }
    
    // MARK: - ObjectInteractor Delegate
    override func arObjectInteractor(_ interactor: ARObjectInteractor, requestsObjectAt point: CGPoint,
                                     for alignment: ARRaycastQuery.TargetAlignment,
                                     completionBlock block: @escaping (ARObject?) -> Void) {

        guard self.worldMap == nil,
              arObject.anchor == nil,
              alignment == .horizontal else { return }
        // Disable placing objects when the session is still relocalizing

        updateQueue.async {
            if !self.arObject.isLoaded {
                self.arObject.load()
            }
            block(self.arObject)
        }
    }

    // MARK: - ARObjectView Delegate
    override func objectView(_ view: ARObjectView, made statusView: ARStatusView) {
        super.objectView(view, made: statusView)
        statusView.setRestartBock { (sender) in
            self.restartExperience()
        }
    }
    
    // MARK: - ARSCNViewDelegate
    /// - Tag: RestoreVirtualContent
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard anchor.name == arObject.name,
              arObject.anchor == nil else { return nil }

        arObject.anchor = anchor
        arObject.simdWorldTransform = anchor.transform
        updateQueue.async {
            if !self.arObject.isLoaded {
                self.arObject.load()
            }
            self.sceneView.scene.rootNode.addChildNode(self.arObject)
        }
        return nil
    }

    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {return}
            self.updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
        }
    }
    
    /// - Tag: CheckMappingStatus
    override func session(_ session: ARSession, didUpdate frame: ARFrame) {
        super.session(session, didUpdate: frame)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {return}
            // Enable Save button only when the mapping status is good and an object has been placed
            switch frame.worldMappingStatus {
                case .extending, .mapped:
                    self.saveExperienceButton.isEnabled =
                        self.arObject.anchor != nil && frame.anchors.contains(self.arObject.anchor!)
                default:
                    self.saveExperienceButton.isEnabled = false
            }
        }
    }
    
    // MARK: - ARSessionObserver
    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {return}
            // Inform the user that the session has been interrupted, for example, by presenting an overlay.
            self.sceneView.statusView?.present(message: "Session was interrupted")
        }
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {return}
            // Reset tracking and/or remove existing anchors if consistent tracking is required.
            self.sceneView.statusView?.present(message: "Session interruption ended")
        }
    }
    
    // MARK: - Session configuration
    override func sessionConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = super.sessionConfiguration()
        configuration.planeDetection = .horizontal
        configuration.initialWorldMap = self.worldMap
        return configuration
    }

    override func resetSession() {
        self.arObject.anchor = nil
        self.arObject.stopTrackedRaycast()
        self.arObject.removeFromParentNode()
        super.resetSession()
    }

    override func restartExperience() {
        self.worldMap = nil
        super.restartExperience()
    }
    
    // MARK: - Event handlers
    /// - Tag: GetWorldMap
    @IBAction func saveExperience(_ button: UIButton) {
        worldMapArchiver.saveWorldMap(from: sceneView) { (data, error) in
            if let error = error {
                self.showAlert(title: "Can't save map", message: error.localizedDescription)
            }
            else {
                self.loadExperienceButton.isHidden = false
                self.loadExperienceButton.isEnabled = true
            }
        }
    }
    
    // Called opportunistically to verify that map data can be loaded from filesystem.
    /// - Tag: RunWithWorldMap
    @IBAction func loadExperience(_ button: UIButton) {
        worldMapArchiver.loadWorldMap { (worldMap, image, error) in
            if let error = error {
                self.showAlert(title: "Can't load map", message: error.localizedDescription)
            }
            else {
                self.worldMap = worldMap
                self.snapshotThumbnail.image = image
                self.resetSession()
            }
        }
    }

    // MARK: - UI Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Read in any already saved map to see if we can load one.
        if worldMapArchiver.fileExists() {
            self.loadExperienceButton.isHidden = false
        }
    }
}

