//
//  Item.swift
//  lanlu
//
//  Created by Deerio on 2026/7/8.
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
