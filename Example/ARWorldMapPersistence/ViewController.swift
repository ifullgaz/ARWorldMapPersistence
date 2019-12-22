/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import ARKit
import ARObject
import ARWorldMapPersistence
import IFGExtensions

class ViewController: ARObjectViewController, ARWorldMapPersistence {
    // MARK: - IBOutlets
    
    @IBOutlet weak var sessionInfoView: UIView!
    @IBOutlet weak var sessionInfoLabel: UILabel!
    @IBOutlet weak var saveExperienceButton: UIButton!
    @IBOutlet weak var loadExperienceButton: UIButton!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var snapshotThumbnail: UIImageView!
    
    var virtualObjectAnchor: ARAnchor?

    let virtualObjectAnchorName = "virtualObject"

    var virtualObject: SCNNode = {
        guard let sceneURL = Bundle.main.url(forResource: "cup", withExtension: "scn", subdirectory: "Assets.scnassets/cup"),
            let referenceNode = SCNReferenceNode(url: sceneURL) else {
                fatalError("can't load virtual object")
        }
        referenceNode.load()
        return referenceNode
    }()

    lazy var mapSaveURL: URL = {
        do {
            return try FileManager.default
                .url(for: .documentDirectory,
                     in: .userDomainMask,
                     appropriateFor: nil,
                     create: true)
                .appendingPathComponent("map.arexperience")
        } catch {
            fatalError("Can't get file save URL: \(error.localizedDescription)")
        }
    }()
    
    var mapDataFromFile: Data? {
        return try? Data(contentsOf: mapSaveURL)
    }
    
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
            if frame.anchors.contains(where: { $0.name == virtualObjectAnchorName }) {
                // User has placed an object in scene and the session is mapped, prompt them to save the experience
                message = "Tap 'Save Experience' to save the current map."
            } else {
                message = "Tap on the screen to place an object."
            }
            
        case (.normal, _) where mapDataFromFile != nil && !isRelocalizingMap:
            message = "Move around to map the environment or tap 'Load Experience' to load a saved experience."
            
        case (.normal, _) where mapDataFromFile == nil:
            message = "Move around to map the environment."
            
        case (.limited(.relocalizing), _) where isRelocalizingMap:
            message = "Move your device to the location shown in the image."
            snapshotThumbnail.isHidden = false
            
        default:
            message = trackingState.feedback
        }
        
        sessionInfoLabel.text = message
        sessionInfoView.isHidden = message.isEmpty
    }
    
    // MARK: - ARSCNViewDelegate
    /// - Tag: RestoreVirtualContent
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard anchor.name == virtualObjectAnchorName
            else { return }
        
        // save the reference to the virtual object anchor when the anchor is added from relocalizing
        if virtualObjectAnchor == nil {
            virtualObjectAnchor = anchor
        }
        node.addChildNode(virtualObject)
    }
    
    // MARK: - ARSessionDelegate
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        updateSessionInfoLabel(for: session.currentFrame!, trackingState: camera.trackingState)
    }
    
    /// - Tag: CheckMappingStatus
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Enable Save button only when the mapping status is good and an object has been placed
        switch frame.worldMappingStatus {
        case .extending, .mapped:
            saveExperienceButton.isEnabled =
                virtualObjectAnchor != nil && frame.anchors.contains(virtualObjectAnchor!)
        default:
            saveExperienceButton.isEnabled = false
        }
        statusLabel.text = """
        Mapping: \(String(describing:frame.worldMappingStatus))
        Tracking: \(String(describing:frame.camera.trackingState))
        """
        updateSessionInfoLabel(for: frame, trackingState: frame.camera.trackingState)
    }
    
    // MARK: - ARSessionObserver
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay.
        sessionInfoLabel.text = "Session was interrupted"
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required.
        sessionInfoLabel.text = "Session interruption ended"
    }
    
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return true
    }
    
    // MARK: - Session configuration
    override func sessionConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = super.sessionConfiguration()
        configuration.planeDetection = .horizontal
        configuration.initialWorldMap = self.worldMap
        return configuration
    }

    // MARK: - Event handlers
    /// - Tag: GetWorldMap
    @IBAction func saveExperience(_ button: UIButton) {
        getWorldMapData(from: sceneView) { worldMapData, error in
            do {
                if let error = error {
                    throw error
                }
                try worldMapData?.write(to: self.mapSaveURL, options: [.atomic])
                DispatchQueue.main.async {
                    self.loadExperienceButton.isHidden = false
                    self.loadExperienceButton.isEnabled = true
                }
            } catch {
                self.showAlert(title: "Can't save map", message: error.localizedDescription)
            }
        }
    }
    
    // Called opportunistically to verify that map data can be loaded from filesystem.
    /// - Tag: RunWithWorldMap
    @IBAction func loadExperience(_ button: UIButton) {
        if let worldMapData = self.mapDataFromFile {
            self.getWorldMap(from: worldMapData) { worldMap, snapshot, error in
                self.snapshotThumbnail.image = snapshot
                self.worldMap = worldMap
                self.isRelocalizingMap = true
                self.virtualObjectAnchor = nil
                self.resetSession()
            }
        }
        else {
            self.showAlert(title: "Can't load map", message: "Data file couldn't be loaded")
        }
    }

    @IBAction func resetTracking(_ sender: UIButton?) {
        self.worldMap = nil
        self.isRelocalizingMap = false
        self.virtualObjectAnchor = nil
        self.resetSession()
    }
    
    // MARK: - Placing AR Content
    /// - Tag: PlaceObject
    @IBAction func handleSceneTap(_ sender: UITapGestureRecognizer) {
        // Disable placing objects when the session is still relocalizing
        if isRelocalizingMap && virtualObjectAnchor == nil {
            return
        }
        // Hit test to find a place for a virtual object.
        guard let hitTestResult = sceneView
            .hitTest(sender.location(in: sceneView), types: [.existingPlaneUsingGeometry, .estimatedHorizontalPlane])
            .first
            else { return }
        
        // Remove exisitng anchor and add new anchor
        if let existingAnchor = virtualObjectAnchor {
            sceneView.session.remove(anchor: existingAnchor)
        }
        virtualObjectAnchor = ARAnchor(name: virtualObjectAnchorName, transform: hitTestResult.worldTransform)
        sceneView.session.add(anchor: virtualObjectAnchor!)
    }

    // MARK: - UI Life cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Read in any already saved map to see if we can load one.
        if mapDataFromFile != nil {
            self.loadExperienceButton.isHidden = false
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        guard ARWorldTrackingConfiguration.isSupported else {
            fatalError("""
                ARKit is not available on this device. For apps that require ARKit
                for core functionality, use the `arkit` key in the key in the
                `UIRequiredDeviceCapabilities` section of the Info.plist to prevent
                the app from installing. (If the app can't be installed, this error
                can't be triggered in a production scenario.)
                In apps where AR is an additive feature, use `isSupported` to
                determine whether to show UI for launching AR experiences.
            """) // For details, see https://developer.apple.com/documentation/arkit
        }
        super.viewWillAppear(animated)
        
        // Prevent the screen from being dimmed after a while as users will likely
        // have long periods of interaction without touching the screen or buttons.
        UIApplication.shared.isIdleTimerDisabled = true
    }

//    // Lock the orientation of the app to the orientation in which it is launched
//    override var shouldAutorotate: Bool {
//        return false
//    }
}

