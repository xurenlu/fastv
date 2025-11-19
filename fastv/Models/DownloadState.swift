//
//  DownloadState.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

enum DownloadState {
    case idle
    case fetchingInfo
    case downloading(Double) // 进度 0.0 - 1.0
    case completed(URL)
    case failed(Error)
}

