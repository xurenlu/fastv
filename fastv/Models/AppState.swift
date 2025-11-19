//
//  AppState.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation

enum AppState: Equatable {
    case empty                    // 空状态：显示拖拽区域
    case singleVideo(URL)         // 单视频：显示预览和处理
    case multipleVideos([URL])   // 多视频：显示列表和批量处理
    
    var videoURLs: [URL] {
        switch self {
        case .empty:
            return []
        case .singleVideo(let url):
            return [url]
        case .multipleVideos(let urls):
            return urls
        }
    }
    
    var isEmpty: Bool {
        if case .empty = self {
            return true
        }
        return false
    }
    
    var isSingleVideo: Bool {
        if case .singleVideo = self {
            return true
        }
        return false
    }
    
    var isMultipleVideos: Bool {
        if case .multipleVideos = self {
            return true
        }
        return false
    }
}

