//
//  VideoInfoView.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//

import SwiftUI

struct VideoInfoView: View {
    let videoInfo: VideoInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("视频信息")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "时长", value: videoInfo.durationString)
                InfoRow(label: "分辨率", value: videoInfo.resolutionString)
                InfoRow(label: "帧率", value: String(format: "%.2f fps", videoInfo.frameRate))
                InfoRow(label: "文件大小", value: videoInfo.fileSizeString)
                
                if !videoInfo.audioTracks.isEmpty {
                    Divider()
                    Text("音频轨道")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(videoInfo.audioTracks.enumerated()), id: \.offset) { index, track in
                        InfoRow(
                            label: "轨道 \(index + 1)",
                            value: "\(track.sampleRateString) · \(track.channelsString)"
                        )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

#Preview {
    VideoInfoView(
        videoInfo: VideoInfo(
            duration: 125.5,
            resolution: CGSize(width: 1920, height: 1080),
            frameRate: 30.0,
            fileSize: 125_000_000,
            audioTracks: [
                AudioTrackInfo(sampleRate: 44100, channels: 2)
            ]
        )
    )
    .padding()
}

