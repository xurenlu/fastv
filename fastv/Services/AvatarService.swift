//
//  AvatarService.swift
//  fastv
//
//  Created by rocky on 2025/01/XX.
//

import Foundation
import AppKit
import CryptoKit

/// 头像服务（Gravatar + Clearbit + Identicon）
class AvatarService {
    static let shared = AvatarService()
    
    private let cacheDirectory: URL
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        // 创建缓存目录
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("EmailAvatars")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // 设置缓存限制
        cache.countLimit = 500
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    /// 获取头像（优先使用缓存）
    func getAvatar(for email: String, size: Int = 80) async -> NSImage? {
        let cacheKey = "\(email)-\(size)"
        
        // 检查内存缓存
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }
        
        // 检查磁盘缓存
        if let diskCached = loadFromDisk(email: email, size: size) {
            cache.setObject(diskCached, forKey: cacheKey as NSString)
            return diskCached
        }
        
        // 尝试从Gravatar获取
        if let gravatar = await fetchGravatar(email: email, size: size) {
            saveToDisk(image: gravatar, email: email, size: size)
            cache.setObject(gravatar, forKey: cacheKey as NSString)
            return gravatar
        }
        
        // 尝试从Clearbit获取（域名logo）
        if let clearbit = await fetchClearbitLogo(email: email) {
            saveToDisk(image: clearbit, email: email, size: size)
            cache.setObject(clearbit, forKey: cacheKey as NSString)
            return clearbit
        }
        
        // 生成Identicon
        let identicon = generateIdenticon(email: email, size: size)
        saveToDisk(image: identicon, email: email, size: size)
        cache.setObject(identicon, forKey: cacheKey as NSString)
        return identicon
    }
    
    // MARK: - Gravatar
    
    private func fetchGravatar(email: String, size: Int) async -> NSImage? {
        let hash = md5Hash(email.lowercased().trimmingCharacters(in: .whitespaces))
        let urlString = "https://www.gravatar.com/avatar/\(hash)?s=\(size)&d=404"
        
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
    
    // MARK: - Clearbit Logo
    
    private func fetchClearbitLogo(email: String) async -> NSImage? {
        guard let domain = email.components(separatedBy: "@").last else { return nil }
        let urlString = "https://logo.clearbit.com/\(domain)"
        
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            return NSImage(data: data)
        } catch {
            return nil
        }
    }
    
    // MARK: - Identicon Generation
    
    private func generateIdenticon(email: String, size: Int) -> NSImage {
        // 简单的Identicon生成（基于邮箱hash）
        let hash = md5Hash(email)
        let hashBytes = Array(hash.utf8)
        
        // 创建图像
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        
        // 使用hash的前几个字节作为颜色
        let r = CGFloat(hashBytes[0]) / 255.0
        let g = CGFloat(hashBytes[1]) / 255.0
        let b = CGFloat(hashBytes[2]) / 255.0
        let color = NSColor(red: r, green: g, blue: b, alpha: 1.0)
        
        // 绘制背景
        color.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        
        // 绘制对称图案（基于hash）
        let patternSize = size / 5
        for i in 0..<5 {
            for j in 0..<3 {
                let byteIndex = (i * 3 + j) % hashBytes.count
                let shouldFill = hashBytes[byteIndex] % 2 == 0
                
                if shouldFill {
                    let rect = NSRect(
                        x: CGFloat(i * patternSize),
                        y: CGFloat(j * patternSize),
                        width: CGFloat(patternSize),
                        height: CGFloat(patternSize)
                    )
                    NSColor.white.setFill()
                    rect.fill()
                    
                    // 对称填充
                    let symmetricRect = NSRect(
                        x: CGFloat((4 - i) * patternSize),
                        y: CGFloat(j * patternSize),
                        width: CGFloat(patternSize),
                        height: CGFloat(patternSize)
                    )
                    symmetricRect.fill()
                }
            }
        }
        
        image.unlockFocus()
        return image
    }
    
    // MARK: - Cache Management
    
    private func saveToDisk(image: NSImage, email: String, size: Int) {
        let filename = "\(md5Hash(email))-\(size).png"
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return
        }
        
        try? pngData.write(to: fileURL)
    }
    
    private func loadFromDisk(email: String, size: Int) -> NSImage? {
        let filename = "\(md5Hash(email))-\(size).png"
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let image = NSImage(contentsOf: fileURL) else {
            return nil
        }
        
        return image
    }
    
    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

