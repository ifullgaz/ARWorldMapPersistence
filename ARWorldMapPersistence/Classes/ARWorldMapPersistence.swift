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
    func getWorldMapData(from view: ARSCNView, block: @escaping (Data?, Error?) -> Void)
    func getWorldMap(from data: Data, block: @escaping (ARWorldMap?, UIImage?, Error?) -> Void)
}

public extension ARWorldMapPersistence {
    func getWorldMapData(from view: ARSCNView, block: @escaping (Data?, Error?) -> Void) {
        view.session.getCurrentWorldMap { worldMap, error in
            DispatchQueue.global(qos: .default).async {
                var data: Data?
                var err: ARWorldMapPersistenceError?
                if let map = worldMap {
                    // Add a snapshot image indicating where the map was captured.
                    if let snapshotAnchor = ARSnapshotAnchor(capturing: view) {
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
                DispatchQueue.main.async {
                    block(data, err)
                }
            }
        }
    }

    func getWorldMap(from data: Data, block: @escaping (ARWorldMap?, UIImage?, Error?) -> Void) {
        DispatchQueue.global(qos: .default).async {
            var worldMap: ARWorldMap?
            var snapshot: UIImage?
            var err: ARWorldMapPersistenceError?
            do {
                guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                    throw ARWorldMapPersistenceError.cantLoadWorldMap(reason: "No world map in archive")
                }
                worldMap = map
                // Display the snapshot image stored in the world map to aid user in relocalizing.
                if let snapshotData = worldMap!.snapshotAnchor?.imageData,
                   let snapshotImage = UIImage(data: snapshotData) {
                    snapshot = snapshotImage
                }
                // Remove the snapshot anchor from the world map since we do not need it in the scene.
                worldMap!.anchors.removeAll(where: { $0 is ARSnapshotAnchor })
            } catch let error as ARWorldMapPersistenceError {
                err = error
            } catch {
                err = .cantLoadWorldMap(reason: error.localizedDescription)
            }
            DispatchQueue.main.async {
                block(worldMap, snapshot, err)
            }
        }
    }
}
