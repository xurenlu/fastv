//
//  VideoItem.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AppKit
import Combine

class VideoItem: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    @Published var videoInfo: VideoInfo?
    @Published var previewImage: NSImage?
    @Published var isSelected: Bool
    @Published var processingState: VideoProcessingState = .pending
    @Published var progress: Double = 0.0
    @Published var processingStatus: String = ""
    
    // 处理结果
    @Published var firstFrameImage: NSImage?
    @Published var lastFrameImage: NSImage?
    @Published var audioURL: URL?
    @Published var outputDirectory: URL?
    
    var fileName: String {
        url.lastPathComponent
    }
    
    init(url: URL, isSelected: Bool = true) {
        self.url = url
        self.isSelected = isSelected
    }
}

enum VideoProcessingState {
    case pending       // 待处理
    case processing    // 处理中
    case completed     // 已完成
    case failed(Error) // 失败
}

