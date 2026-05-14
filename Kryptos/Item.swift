//
//  Item.swift
//  Kryptos
//
//  Created by Faizal Zain on 14/05/2026.
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
