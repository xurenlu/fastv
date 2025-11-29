//
//  HistoryRecordManagementView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 历史记录管理视图

struct HistoryRecordManagementView: View {
    @ObservedObject private var history = VoiceInputHistory.shared
    @State private var showExportAlert = false
    @State private var exportMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 统计信息
            VStack(alignment: .leading, spacing: 4) {
                Text("历史记录总数")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(history.allItems.count) 条")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            Divider()
            
            // 导出按钮
            Button(action: {
                exportHistory()
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("导出历史记录")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .alert("导出结果", isPresented: $showExportAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(exportMessage)
        }
    }
    
    private func exportHistory() {
        guard let jsonData = try? JSONEncoder().encode(history.allItems) else {
            exportMessage = "导出失败：无法编码数据"
            showExportAlert = true
            return
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "voice_input_history_\(dateString()).json"
        
        if savePanel.runModal() == .OK,
           let url = savePanel.url {
            do {
                try jsonData.write(to: url)
                exportMessage = "历史记录已导出到：\(url.path)"
                showExportAlert = true
            } catch {
                exportMessage = "导出失败：\(error.localizedDescription)"
                showExportAlert = true
            }
        }
    }
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}

