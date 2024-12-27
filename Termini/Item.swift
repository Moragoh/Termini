//
//  Item.swift
//  Termini
//
//  Created by Jun Min Kim on 12/27/24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
