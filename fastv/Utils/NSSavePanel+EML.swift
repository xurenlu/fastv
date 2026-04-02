//
//  NSSavePanel+EML.swift
//  fastv
//

import AppKit
import UniformTypeIdentifiers

extension NSSavePanel {
    /// 设置保存为 .eml 类型；避免对 `UTType(filenameExtension:)` 强制解包导致崩溃
    func applyEMLContentTypes() {
        if let eml = UTType(filenameExtension: "eml") {
            allowedContentTypes = [eml]
        } else {
            allowedContentTypes = []
            allowedFileTypes = ["eml"]
        }
    }
}
