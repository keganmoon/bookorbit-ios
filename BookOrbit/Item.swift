//
//  Item.swift
//  BookOrbit
//
//  Created by Kegan on 6/6/26.
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
