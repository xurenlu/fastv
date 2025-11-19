//
//  CoreMLWrapper.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//
//  使用 CoreML 运行语音识别模型
//  需要先将 ONNX 模型转换为 CoreML 格式（使用 convert_to_coreml.py）
//

import Foundation
import CoreML

/// CoreML 包装类 - 使用 Apple 原生框架运行模型
class CoreMLWrapper {
    private var model: MLModel?
    
    /// 加载 CoreML 模型
    func loadModel(from path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw VideoProcessingError.modelLoadFailed("模型文件不存在: \(path)")
        }
        
        let modelURL = URL(fileURLWithPath: path)
        
        // 加载 CoreML 模型
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all  // 使用所有可用计算单元（CPU + GPU + Neural Engine）
        
        do {
            model = try MLModel(contentsOf: modelURL, configuration: configuration)
        } catch {
            throw VideoProcessingError.modelLoadFailed("无法加载 CoreML 模型: \(error.localizedDescription)")
        }
    }
    
    /// 运行推理
    /// - Parameter input: 输入特征 [batch_size, sequence_length, feature_dim]
    /// - Returns: 输出 token IDs
    func runInference(input: [[[Float]]]) throws -> [Int] {
        guard let model = model else {
            throw VideoProcessingError.modelLoadFailed("模型未加载，请先加载模型")
        }
        
        guard !input.isEmpty, !input[0].isEmpty, !input[0][0].isEmpty else {
            throw VideoProcessingError.transcriptionFailed("输入数据为空")
        }
        
        // 准备输入
        let batchSize = 1
        let sequenceLength = input[0].count
        let featureDim = input[0][0].count
        
        // 获取模型描述以查看所需的输入
        let modelDescription = model.modelDescription
        let inputDescriptions = modelDescription.inputDescriptionsByName
        
        #if DEBUG
        print("CoreML 模型输入要求:")
        for (name, desc) in inputDescriptions {
            print("  - \(name): \(desc.type)")
        }
        print("CoreML 模型输出:")
        for (name, desc) in modelDescription.outputDescriptionsByName {
            print("  - \(name): \(desc.type)")
        }
        #endif
        
        // 展平输入数据
        let flatInput = input[0].flatMap { $0 }
        
        // 创建多维数组（CoreML 需要）
        // 形状：[batch, sequence_length, feature_dim]
        let shape = [NSNumber(value: batchSize), NSNumber(value: sequenceLength), NSNumber(value: featureDim)]
        
        // 创建 MLMultiArray
        guard let speechArray = try? MLMultiArray(shape: shape, dataType: .float32) else {
            throw VideoProcessingError.transcriptionFailed("无法创建输入数组")
        }
        
        // 填充数据
        for (index, value) in flatInput.enumerated() {
            speechArray[index] = NSNumber(value: value)
        }
        
        // 构建输入字典，尝试包含所有可能的输入
        var inputDict: [String: Any] = [:]
        
        // 1. speech 输入（主要音频特征）
        if inputDescriptions["speech"] != nil {
            inputDict["speech"] = speechArray
        } else if inputDescriptions["input"] != nil {
            inputDict["input"] = speechArray
        } else {
            // 如果没有找到，使用第一个输入名称
            if let firstName = inputDescriptions.keys.first {
                inputDict[firstName] = speechArray
            } else {
                inputDict["speech"] = speechArray
            }
        }
        
        // 2. speech_lengths 输入（序列长度）
        if inputDescriptions["speech_lengths"] != nil {
            let lengthsShape = [NSNumber(value: batchSize)]
            if let lengthsArray = try? MLMultiArray(shape: lengthsShape, dataType: .int32) {
                lengthsArray[0] = NSNumber(value: Int32(sequenceLength))
                inputDict["speech_lengths"] = lengthsArray
            }
        }
        
        // 3. language 输入（语言标识，0=中文）
        if inputDescriptions["language"] != nil {
            let languageShape = [NSNumber(value: batchSize)]
            if let languageArray = try? MLMultiArray(shape: languageShape, dataType: .int32) {
                languageArray[0] = NSNumber(value: 0) // 0 = 中文
                inputDict["language"] = languageArray
            }
        }
        
        // 4. textnorm 输入（文本规范化，0=禁用）
        if inputDescriptions["textnorm"] != nil {
            let textnormShape = [NSNumber(value: batchSize)]
            if let textnormArray = try? MLMultiArray(shape: textnormShape, dataType: .int32) {
                textnormArray[0] = NSNumber(value: 0) // 0 = 禁用文本规范化
                inputDict["textnorm"] = textnormArray
            }
        }
        
        #if DEBUG
        print("实际使用的输入:")
        for (name, _) in inputDict {
            print("  - \(name)")
        }
        #endif
        
        // 运行推理
        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: inputDict))
        } catch {
            #if DEBUG
            print("推理错误详情: \(error)")
            print("尝试的输入键: \(inputDict.keys.joined(separator: ", "))")
            #endif
            throw VideoProcessingError.transcriptionFailed("推理失败: \(error.localizedDescription)")
        }
        
        // 获取输出
        // 注意：输出名称可能需要根据实际模型调整
        // SenseVoice 模型的输出可能是 "text" 或 "output"
        var outputFeature: MLFeatureValue?
        
        if let textOutput = prediction.featureValue(for: "text") {
            outputFeature = textOutput
        } else if let outputOutput = prediction.featureValue(for: "output") {
            outputFeature = outputOutput
        } else {
            // 获取第一个输出
            let outputNames = prediction.featureNames
            if let firstName = outputNames.first {
                outputFeature = prediction.featureValue(for: firstName)
            }
        }
        
        guard let output = outputFeature else {
            throw VideoProcessingError.transcriptionFailed("无法获取模型输出，请检查输出名称")
        }
        
        // 提取 token IDs
        var tokenIDs: [Int] = []
        
        if let multiArray = output.multiArrayValue {
            // MLMultiArray 输出
            let count = multiArray.count
            let shape = multiArray.shape.map { $0.intValue }
            
            #if DEBUG
            print("CoreML 输出形状: \(shape), 数据类型: \(multiArray.dataType.rawValue), 元素数量: \(count)")
            #endif
            
            // CoreML 的 MLMultiArrayDataType 使用不同的值
            // .int32 = 0x1000002, .double = 0x2000001, .float32 = 0x2000002
            // 检查数据类型并提取值
            switch multiArray.dataType {
            case .int32:
                let pointer = multiArray.dataPointer.bindMemory(to: Int32.self, capacity: count)
                for i in 0..<count {
                    tokenIDs.append(Int(pointer[i]))
                }
            case .double:
                let pointer = multiArray.dataPointer.bindMemory(to: Double.self, capacity: count)
                for i in 0..<count {
                    tokenIDs.append(Int(pointer[i]))
                }
            case .float32:
                // 可能是 CTC logits，需要 argmax 解码
                let pointer = multiArray.dataPointer.bindMemory(to: Float.self, capacity: count)
                
                // 检查是否是 CTC logits 格式 [batch, sequence_length, vocab_size]
                if shape.count == 3 && shape[0] == 1 {
                    // CTC logits 格式：对每个时间步执行 argmax
                    let sequenceLength = shape[1]
                    let vocabSize = shape[2]
                    
                    #if DEBUG
                    print("检测到 CTC logits 格式: sequence_length=\(sequenceLength), vocab_size=\(vocabSize)")
                    #endif
                    
                    for t in 0..<sequenceLength {
                        var maxValue: Float = -Float.infinity
                        var maxIndex: Int = 0
                        
                        let startIdx = t * vocabSize
                        let endIdx = startIdx + vocabSize
                        
                        for i in startIdx..<endIdx {
                            if i < count {
                                let value = pointer[i]
                                if value > maxValue {
                                    maxValue = value
                                    maxIndex = i - startIdx
                                }
                            }
                        }
                        
                        tokenIDs.append(maxIndex)
                    }
                } else if shape.count == 2 && shape[0] == 1 {
                    // 可能是 [batch, sequence_length] 格式，直接取最大值索引
                    let sequenceLength = shape[1]
                    let vocabSize = count / sequenceLength
                    
                    #if DEBUG
                    print("检测到 2D 输出格式: sequence_length=\(sequenceLength), vocab_size=\(vocabSize)")
                    #endif
                    
                    for t in 0..<sequenceLength {
                        var maxValue: Float = -Float.infinity
                        var maxIndex: Int = 0
                        
                        let startIdx = t * vocabSize
                        let endIdx = startIdx + vocabSize
                        
                        for i in startIdx..<endIdx {
                            if i < count {
                                let value = pointer[i]
                                if value > maxValue {
                                    maxValue = value
                                    maxIndex = i - startIdx
                                }
                            }
                        }
                        
                        tokenIDs.append(maxIndex)
                    }
                } else {
                    // 1D 输出，直接转换为 token IDs（取整）
                for i in 0..<count {
                    tokenIDs.append(Int(pointer[i]))
                    }
                }
            default:
                // 尝试作为 Int32 处理
                let pointer = multiArray.dataPointer.bindMemory(to: Int32.self, capacity: count)
                for i in 0..<count {
                    tokenIDs.append(Int(pointer[i]))
                }
            }
        } else {
            // 尝试从其他格式提取
            // MLFeatureValue 可能包含其他类型的数据
            throw VideoProcessingError.transcriptionFailed("无法解析输出格式，期望 MLMultiArray")
        }
        
        #if DEBUG
        print("CoreML 提取的 token IDs: \(tokenIDs.prefix(20))... (共 \(tokenIDs.count) 个)")
        #endif
        
        return tokenIDs
    }
    
    deinit {
        model = nil
    }
}

