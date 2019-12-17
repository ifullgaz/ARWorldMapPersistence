//
//  ARViewController+ARMapPersistence.swift
//  shopper2
//
//  Created by Emmanuel Merali on 17/12/2019.
//  Copyright © 2019 Trax Retail. All rights reserved.
//

import ARKit

public enum ARWorldMapPersistenceError: Error {
    case cantGetWorldMap(reason: String)
    case cantGetWorldMapSnapshot
    case cantLoadWorldMap(reason: String)
    case cantSaveWorldMap(reason: String)
    
    var title: String {
        switch self {
            case .cantGetWorldMap:
                return "Can't get current world map"
            case .cantGetWorldMapSnapshot:
                return "Can't get current world map snapshot"
            case .cantLoadWorldMap:
                return "Can't load current world map"
            case .cantSaveWorldMap:
                return "Can't save current world map"
        }
    }
    
    var reason: String {
        switch self {
            case .cantGetWorldMap(let reason):
                fallthrough
            case .cantLoadWorldMap(let reason):
                fallthrough
            case .cantSaveWorldMap(let reason):
                return reason
            case .cantGetWorldMapSnapshot:
                return ""
        }
    }

    public var localizedDescription: String {
        return "\(title)\n\(reason)"
    }
}

public protocol ARWorldMapPersistence {
    func worldMapData(from view: ARSCNView, block: @escaping (Data?, Error?) -> Void)
    func worldMap(from data: Data) throws -> (ARWorldMap, UIImage?)?
}

public extension ARWorldMapPersistence {
    func worldMapData(from view: ARSCNView, block: @escaping (Data?, Error?) -> Void) {
        
        view.session.getCurrentWorldMap { worldMap, error in
            var err: ARWorldMapPersistenceError?
            var data: Data?
            
            if let map = worldMap {
                // Add a snapshot image indicating where the map was captured.
                if let snapshotAnchor = SnapshotAnchor(capturing: view) {
                    map.anchors.append(snapshotAnchor)
                    do {
                        data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                    } catch {
                        err = .cantSaveWorldMap(reason: error.localizedDescription)
                    }
                } else {
                    err = .cantGetWorldMapSnapshot
                }
            } else {
                err = .cantGetWorldMap(reason: error!.localizedDescription)
            }

            block(data, err)
        }
    }
    
    func worldMap(from data: Data) throws -> (ARWorldMap, UIImage?)? {
        var snapshot: UIImage?
        do {
            guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                throw ARWorldMapPersistenceError.cantLoadWorldMap(reason: "No world map in archive")
            }
            // Display the snapshot image stored in the world map to aid user in relocalizing.
            if let snapshotData = worldMap.snapshotAnchor?.imageData,
               let snapshotImage = UIImage(data: snapshotData) {
                snapshot = snapshotImage
            }
            // Remove the snapshot anchor from the world map since we do not need it in the scene.
            worldMap.anchors.removeAll(where: { $0 is SnapshotAnchor })
            return (worldMap, snapshot)
        } catch let error as ARWorldMapPersistenceError {
            throw error
        } catch {
            throw ARWorldMapPersistenceError.cantLoadWorldMap(reason: "Unarchiving failed")
        }
    }
}
