//
//  FrameQueue.swift
//  Quick3D
//
//  Created by HungNT on 27/11/25.
//

import Foundation
import ARKit

struct FrameQueue {
    private var elements: [FrameCache] = []

    mutating func enqueue(_ value: FrameCache) {
        elements.removeAll { item in
            item.frame?.timestamp == value.frame?.timestamp
        }
        elements.append(value)
    }

    mutating func dequeue() -> FrameCache? {
        guard !elements.isEmpty else {
          return nil
        }
        return elements.removeFirst()
    }

    mutating func dequeueAll() {
        elements = []
    }

    var head: FrameCache? {
        return elements.first
    }

    var tail: FrameCache? {
        return elements.last
    }

    mutating func dequeue(timeStamp: TimeInterval) {
        guard !elements.isEmpty else {
          return
        }

        elements.removeAll { item in
            item.frame?.timestamp == timeStamp
        }
    }

    func isInQueue(timeStamp: TimeInterval?) -> Bool {
        guard let timeStamp = timeStamp else {
            return false
        }
        if elements.isEmpty {
          return false
        }
        if elements.first(where: { $0.frame?.timestamp == timeStamp }) != nil {
            return true
        }
        return false
    }
    
    func getCount() -> Int {
        return elements.count
    }
}
