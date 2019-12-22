/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A custom anchor for saving a snapshot image in an ARWorldMap.
*/

import ARKit

private extension CGImagePropertyOrientation {
    /// Preferred image presentation orientation respecting the native sensor orientation of iOS device camera.
    init(cameraOrientation: UIDeviceOrientation) {
        switch cameraOrientation {
        case .portraitUpsideDown:
            self = .left
        case .landscapeLeft:
            self = .up
        case .landscapeRight:
            self = .down
        case .portrait:
            self = .right
        default:
            self = .right
        }
    }
}

public class ARSnapshotAnchor: ARAnchor {
    
    public var imageData: Data?
    
    public convenience init?(capturing view: ARSCNView) {
        guard let frame = view.session.currentFrame
            else { return nil }
        
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        let orientation = CGImagePropertyOrientation(cameraOrientation: UIDevice.current.orientation)
        
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let data = context.jpegRepresentation(of: image.oriented(orientation),
                                                    colorSpace: CGColorSpaceCreateDeviceRGB(),
                                                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.7])
            else { return nil }
        
        self.init(imageData: data, transform: frame.camera.transform)
    }
    
    override public class var supportsSecureCoding: Bool {
        return true
    }
        
    override public func encode(with aCoder: NSCoder) {
        super.encode(with: aCoder)
        aCoder.encode(imageData, forKey: "snapshot_data")
    }

    required public override init(name: String, transform: simd_float4x4) {
        super.init(name: name, transform: transform)
    }
    
    public convenience init(imageData: Data, transform: float4x4) {
        self.init(name: "snapshot", transform: transform)
        self.imageData = imageData
    }
    
    required public init(anchor: ARAnchor) {
        if let anchor = anchor as? ARSnapshotAnchor {
            self.imageData = anchor.imageData
        }
        super.init(anchor: anchor)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        if let snapshot = aDecoder.decodeObject(forKey: "snapshot_data") as? Data {
            self.imageData = snapshot
        } else {
            return nil
        }
        
        super.init(coder: aDecoder)
    }
}
