//
//  ARWorldMap+Extensions.swift
//  shopper2
//
//  Created by Emmanuel Merali on 12/12/2019.
//  Copyright © 2019 Trax Retail. All rights reserved.
//

import ARKit

public extension ARWorldMap {
    var snapshotAnchor: ARSnapshotAnchor? {
        return anchors.compactMap { $0 as? ARSnapshotAnchor }.first
    }
}
