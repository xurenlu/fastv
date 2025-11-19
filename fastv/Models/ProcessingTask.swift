//
//  ProcessingTask.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

enum ProcessingTaskType {
    case extractFirstFrame
    case extractLastFrame
    case extractAudio
}

enum ProcessingTaskStatus {
    case pending
    case inProgress
    case completed
    case failed(Error)
}

struct ProcessingTask {
    let type: ProcessingTaskType
    var status: ProcessingTaskStatus = .pending
    var progress: Double = 0.0
}

