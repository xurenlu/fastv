//
//  FileManager+Extensions.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import Foundation
import AppKit

extension FileManager {
    /// 获取默认输出目录（视频文件同目录）
    func defaultOutputDirectory(for videoURL: URL) -> URL {
        return videoURL.deletingLastPathComponent()
    }
    
    /// 生成唯一的文件名（如果文件已存在，添加序号）
    func uniqueFileName(at directory: URL, baseName: String, extension: String) -> String {
        var fileName = "\(baseName).\(`extension`)"
        var counter = 1
        
        while fileExists(atPath: directory.appendingPathComponent(fileName).path) {
            fileName = "\(baseName)_\(counter).\(`extension`)"
            counter += 1
        }
        
        return fileName
    }
    
    /// 打开 Finder 并选中文件
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }
}

