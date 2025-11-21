//
//  ONNXRuntimeWrapper.swift
//  fastv
//
//  Created by rocky on 2025/11/19.
//
//  ONNX Runtime C API 包装类
//  使用 ONNX Runtime C API 通过桥接头文件调用
//

import Foundation

// 通过桥接头文件 ONNXRuntimeBridge.h 访问 C API
// C API 类型和函数在桥接头文件中定义

class ONNXRuntimeWrapper {
    private var session: OpaquePointer? // OrtSession*
    private var env: OpaquePointer? // OrtEnv*
    private var api: UnsafePointer<OrtApi>?
    
    init() {
        // 获取 ONNX Runtime API
        guard let apiBase = OrtGetApiBase() else {
            print("警告：无法获取 ONNX Runtime API Base")
            return
        }
        
        guard let api = apiBase.pointee.GetApi(UInt32(ORT_API_VERSION)) else {
            print("警告：无法获取 ONNX Runtime API")
            return
        }
        
        self.api = api
        
        // 创建环境
        var env: OpaquePointer?
        let logid = "fastv".cString(using: .utf8)
        let status = api.pointee.CreateEnv(
            ORT_LOGGING_LEVEL_WARNING,
            logid,
            &env
        )
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            print("警告：无法初始化 ONNX Runtime 环境: \(errorMsg)")
            return
        }
        
        self.env = env
    }
    
    func loadModel(from path: String) throws {
        guard let api = api else {
            throw VideoProcessingError.modelLoadFailed("API 未初始化")
        }
        
        guard let env = env else {
            throw VideoProcessingError.modelLoadFailed("环境未初始化")
        }
        
        guard FileManager.default.fileExists(atPath: path) else {
            throw VideoProcessingError.modelLoadFailed("模型文件不存在: \(path)")
        }
        
        // 创建会话选项
        var sessionOptions: OpaquePointer?
        var status = api.pointee.CreateSessionOptions(&sessionOptions)
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.modelLoadFailed("无法创建会话选项: \(errorMsg)")
        }
        
        defer {
            if let options = sessionOptions {
                api.pointee.ReleaseSessionOptions(options)
            }
        }
        
        // 创建会话
        // 在 macOS 上，ORTCHAR_T 是 char，所以直接使用 path
        var session: OpaquePointer?
        let pathCString = path.cString(using: .utf8)
        status = api.pointee.CreateSession(
            env,
            pathCString,
            sessionOptions,
            &session
        )
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.modelLoadFailed("无法加载模型: \(errorMsg)")
        }
        
        self.session = session
    }
    
    func runInference(input: [[[Float]]], language: TranscriptLanguage = .auto) throws -> [Int] {
        guard let api = api else {
            throw VideoProcessingError.modelLoadFailed("API 未初始化")
        }
        
        guard let session = session else {
            throw VideoProcessingError.modelLoadFailed("会话未创建，请先加载模型")
        }
        
        guard !input.isEmpty, !input[0].isEmpty, !input[0][0].isEmpty else {
            throw VideoProcessingError.transcriptionFailed("输入数据为空")
        }
        
        // 准备输入数据
        let batchSize: Int64 = 1
        let sequenceLength: Int64 = Int64(input[0].count)
        let featureDim: Int64 = Int64(input[0][0].count)
        
        // 验证输入数据
        guard sequenceLength > 0, featureDim > 0 else {
            throw VideoProcessingError.transcriptionFailed("输入数据维度无效: sequence=\(sequenceLength), feature=\(featureDim)")
        }
        
        // 检查所有帧的维度是否一致
        for (index, frame) in input[0].enumerated() {
            guard frame.count == Int(featureDim) else {
                throw VideoProcessingError.transcriptionFailed("输入数据维度不一致: 帧 \(index) 维度为 \(frame.count)，期望 \(featureDim)")
            }
            
            // 检查 NaN 和 Inf
            for (valueIndex, value) in frame.enumerated() {
                if value.isNaN {
                    throw VideoProcessingError.transcriptionFailed("输入数据包含 NaN: 帧 \(index), 维度 \(valueIndex)")
                }
                if value.isInfinite {
                    throw VideoProcessingError.transcriptionFailed("输入数据包含 Inf: 帧 \(index), 维度 \(valueIndex), 值=\(value)")
                }
            }
        }
        
        let flatInput = input[0].flatMap { $0 }
        
        // 验证展平后的数据大小
        let expectedSize = Int(sequenceLength * featureDim)
        guard flatInput.count == expectedSize else {
            throw VideoProcessingError.transcriptionFailed("输入数据大小不匹配: 实际=\(flatInput.count), 期望=\(expectedSize)")
        }
        
        // 创建内存信息
        var memoryInfo: OpaquePointer?
        var status = api.pointee.CreateCpuMemoryInfo(
            OrtArenaAllocator,
            OrtMemTypeDefault,
            &memoryInfo
        )
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法创建内存信息: \(errorMsg)")
        }
        
        defer {
            if let info = memoryInfo {
                api.pointee.ReleaseMemoryInfo(info)
            }
        }
        
        // 创建输入张量
        let shape: [Int64] = [batchSize, sequenceLength, featureDim]
        var inputTensor: OpaquePointer?
        
        // 创建可变的数据副本用于创建张量
        var inputDataCopy = flatInput
        let inputData = inputDataCopy.withUnsafeMutableBytes { bytes -> UnsafeMutableRawPointer in
            return bytes.baseAddress!
        }
        
        status = api.pointee.CreateTensorWithDataAsOrtValue(
            memoryInfo,
            inputData,
            flatInput.count * MemoryLayout<Float>.size,
            shape,
            3, // shape_len
            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
            &inputTensor
        )
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法创建输入张量: \(errorMsg)")
        }
        
        defer {
            if let tensor = inputTensor {
                api.pointee.ReleaseValue(tensor)
            }
        }
        
        // 动态获取模型的输入输出名称
        let (inputNames, outputNames) = try getModelInputOutputNames(session: session, api: api)
        
        guard !inputNames.isEmpty, !outputNames.isEmpty else {
            throw VideoProcessingError.transcriptionFailed("无法获取模型的输入输出名称")
        }
        
        #if DEBUG
        print("ONNX 模型输入要求: \(inputNames)")
        print("ONNX 模型输出: \(outputNames)")
        print("输入特征形状: batch=\(batchSize), sequence=\(sequenceLength), feature=\(featureDim)")
        print("输入数据统计: 总元素数=\(flatInput.count), min=\(flatInput.min() ?? 0), max=\(flatInput.max() ?? 0), avg=\(flatInput.reduce(0, +) / Float(flatInput.count))")
        #endif
        
        // 创建所有必需的输入张量（按照模型定义的顺序）
        var inputTensors: [OpaquePointer?] = []
        var inputNameStrings: [String] = []
        
        // 按照模型定义的顺序创建输入：speech, speech_lengths, language, textnorm
        // 1. speech 输入（主要音频特征）
        if let tensor = inputTensor {
            inputTensors.append(tensor)
            if let speechIndex = inputNames.firstIndex(of: "speech") {
                inputNameStrings.append(inputNames[speechIndex])
            } else {
                inputNameStrings.append(inputNames[0])
            }
        }
        
        // 2. speech_lengths 输入（序列长度）
        var speechLengthsTensor: OpaquePointer?
        let speechLengthsValue: Int32 = Int32(sequenceLength)
        let speechLengthsData: [Int32] = [speechLengthsValue]
        speechLengthsData.withUnsafeBufferPointer { buffer in
            let shape: [Int64] = [batchSize]
            var tensor: OpaquePointer?
            let status = api.pointee.CreateTensorWithDataAsOrtValue(
                memoryInfo,
                UnsafeMutableRawPointer(mutating: buffer.baseAddress!),
                speechLengthsData.count * MemoryLayout<Int32>.size,
                shape,
                1,
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32,
                &tensor
            )
            if status != nil {
                _ = getErrorMessage(from: status, api: api)
                api.pointee.ReleaseStatus(status)
            } else {
                speechLengthsTensor = tensor
            }
        }
        
        if let tensor = speechLengthsTensor {
            inputTensors.append(tensor)
            // 确保使用正确的输入名称
            if let index = inputNames.firstIndex(of: "speech_lengths") {
                inputNameStrings.append(inputNames[index])
            } else if inputNames.count > 1 {
                inputNameStrings.append(inputNames[1])
            }
        }
        
        // 3. language 输入（语言标识）
        // Python 示例使用字符串 "zh"，但 ONNX 模型底层可能期望整数
        // 根据 Python 代码：language="zh" 表示中文
        // 注意：需要根据模型实际要求调整，可能是整数映射或字符串
        var languageTensor: OpaquePointer?
        
        // 检查模型是否有 language 输入
        // SenseVoice lid_dict: {"auto": 0, "zh": 3, "en": 4, "yue": 7, "ja": 11, "ko": 12, "nospeech": 13}
        // 根据错误信息，模型期望的范围是 [-16, 15]，但 3 在这个范围内，应该可以
        // 使用用户选择的语言ID
        var languageDataValue: Int32 = language.languageID
        if inputNames.contains(where: { $0.contains("language") || $0 == "language" }) {
            // 尝试整数类型（ONNX 模型通常使用整数）
            let languageData: [Int32] = [languageDataValue] // 3 = 中文 (zh)
        languageData.withUnsafeBufferPointer { buffer in
            let shape: [Int64] = [batchSize]
            var tensor: OpaquePointer?
            let status = api.pointee.CreateTensorWithDataAsOrtValue(
                memoryInfo,
                UnsafeMutableRawPointer(mutating: buffer.baseAddress!),
                languageData.count * MemoryLayout<Int32>.size,
                shape,
                1,
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32,
                &tensor
            )
            if status != nil {
                    let errorMsg = getErrorMessage(from: status, api: api)
                api.pointee.ReleaseStatus(status)
                    #if DEBUG
                    print("警告：创建 language 张量失败: \(errorMsg)")
                    #endif
            } else {
                languageTensor = tensor
                    #if DEBUG
                    print("成功创建 language 张量，值=\(languageData[0])")
                    #endif
                }
            }
        }
        
        if let tensor = languageTensor {
            inputTensors.append(tensor)
            if let index = inputNames.firstIndex(of: "language") {
                inputNameStrings.append(inputNames[index])
            } else if let index = inputNames.firstIndex(where: { $0.contains("language") }) {
                inputNameStrings.append(inputNames[index])
            } else if inputNames.count > 2 {
                inputNameStrings.append(inputNames[2])
            }
            
            #if DEBUG
            print("language 参数: \(languageDataValue) (中文)")
            #endif
        }
        
        // 4. textnorm 输入（文本规范化）
        // C# 代码: textnormDict = { "withitn": 14, "woitn": 15 }
        // C# 示例使用: textnormId = 15 (woitn)
        // Python 示例：use_itn=False，对应 textnorm="woitn" -> 15
        var textnormTensor: OpaquePointer?
        let textnormDataValue: Int32 = 15 // 15 = woitn (without ITN，对应 use_itn=False)
        let textnormData: [Int32] = [textnormDataValue]
        textnormData.withUnsafeBufferPointer { buffer in
            let shape: [Int64] = [batchSize]
            var tensor: OpaquePointer?
            let status = api.pointee.CreateTensorWithDataAsOrtValue(
                memoryInfo,
                UnsafeMutableRawPointer(mutating: buffer.baseAddress!),
                textnormData.count * MemoryLayout<Int32>.size,
                shape,
                1,
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32,
                &tensor
            )
            if status != nil {
                let errorMsg = getErrorMessage(from: status, api: api)
                api.pointee.ReleaseStatus(status)
                #if DEBUG
                print("警告：创建 textnorm 张量失败: \(errorMsg)")
                #endif
            } else {
                textnormTensor = tensor
                #if DEBUG
                print("成功创建 textnorm 张量，值=\(textnormDataValue)")
                #endif
            }
        }
        
        if let tensor = textnormTensor {
            inputTensors.append(tensor)
            if let index = inputNames.firstIndex(of: "textnorm") {
                inputNameStrings.append(inputNames[index])
            } else if inputNames.count > 3 {
                inputNameStrings.append(inputNames[3])
            }
        }
        
        // 确保输入数量和名称数量匹配
        guard inputTensors.count == inputNameStrings.count, inputTensors.count == inputNames.count else {
            #if DEBUG
            print("警告：输入数量不匹配 - 张量=\(inputTensors.count), 名称=\(inputNameStrings.count), 模型要求=\(inputNames.count)")
            print("模型要求的输入: \(inputNames)")
            print("实际提供的输入: \(inputNameStrings)")
            #endif
            throw VideoProcessingError.transcriptionFailed("输入数量和名称数量不匹配: 张量=\(inputTensors.count), 名称=\(inputNameStrings.count), 模型要求=\(inputNames.count)")
        }
        
        #if DEBUG
        print("实际使用的输入: \(inputNameStrings)")
        print("输入张量数量: \(inputTensors.count)")
        print("输入名称数量: \(inputNameStrings.count)")
        // 验证输入顺序
        for (index, name) in inputNameStrings.enumerated() {
            print("  输入[\(index)]: \(name)")
        }
        #endif
        
        defer {
            // 清理额外的输入张量
            if let tensor = speechLengthsTensor {
                api.pointee.ReleaseValue(tensor)
            }
            if let tensor = languageTensor {
                api.pointee.ReleaseValue(tensor)
            }
            if let tensor = textnormTensor {
                api.pointee.ReleaseValue(tensor)
            }
        }
        
        // 使用 ctc_logits 输出（CTC logits）
        // 注意：SenseVoice 模型输出 ["ctc_logits", "encoder_out_lens"]
        // 我们需要 ctc_logits 进行 CTC 解码，encoder_out_lens 用于确定实际序列长度
        let ctcLogitsOutputName = outputNames.first(where: { $0.contains("ctc_logits") || $0 == "ctc_logits" }) ?? outputNames[0]
        let encoderOutLensOutputName = outputNames.first(where: { $0.contains("encoder_out_lens") || $0.contains("lens") }) ?? (outputNames.count > 1 ? outputNames[1] : nil)
        
        #if DEBUG
        print("使用输出: ctc_logits=\(ctcLogitsOutputName), encoder_out_lens=\(encoderOutLensOutputName ?? "无")")
        #endif
        
        var outputValues: [OpaquePointer?] = [nil]
        if encoderOutLensOutputName != nil {
            outputValues.append(nil) // 为 encoder_out_lens 预留位置
        }
        
        // 创建运行选项
        var runOptions: OpaquePointer?
        status = api.pointee.CreateRunOptions(&runOptions)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法创建运行选项: \(errorMsg)")
        }
        
        defer {
            if let options = runOptions {
                api.pointee.ReleaseRunOptions(options)
            }
        }
        
        // 准备输入名称数组（C 字符串指针数组）
        // 使用 withCString 确保字符串生命周期
        var currentStatus: OrtStatusPtr?
        
        // 为每个输入名称创建 C 字符串（使用 cString 返回的指针在整个函数调用期间有效）
        let inputNameCStrings = inputNameStrings.map { $0.cString(using: .utf8)! }
        var inputNamePtrs: [UnsafePointer<CChar>?] = inputNameCStrings.map { UnsafePointer($0) }
        
        // 准备输出名称 C 字符串
        let ctcLogitsCString = ctcLogitsOutputName.cString(using: .utf8)!
        var outputNamePtrs: [UnsafePointer<CChar>?] = [UnsafePointer(ctcLogitsCString)]
        var encoderOutLensCString: [CChar]? = nil
        if let encoderOutLensName = encoderOutLensOutputName {
            encoderOutLensCString = encoderOutLensName.cString(using: .utf8)!
            outputNamePtrs.append(UnsafePointer(encoderOutLensCString!))
        }
        
        // 运行推理（使用 withExtendedLifetime 确保字符串生命周期）
        if let encoderOutLensCString = encoderOutLensCString {
            withExtendedLifetime((inputNameCStrings, ctcLogitsCString, encoderOutLensCString)) {
                currentStatus = api.pointee.Run(
                    session,
                    runOptions,
                    &inputNamePtrs,
                    inputTensors.withUnsafeBufferPointer { $0.baseAddress },
                    inputTensors.count,
                    &outputNamePtrs,
                    outputNamePtrs.count,
                    &outputValues
                )
            }
        } else {
            withExtendedLifetime((inputNameCStrings, ctcLogitsCString)) {
                currentStatus = api.pointee.Run(
                    session,
                    runOptions,
                    &inputNamePtrs,
                    inputTensors.withUnsafeBufferPointer { $0.baseAddress },
                    inputTensors.count,
                    &outputNamePtrs,
                    outputNamePtrs.count,
                    &outputValues
                )
            }
        }
        
        status = currentStatus
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("推理失败: \(errorMsg)")
        }
        
        // 成功
        guard let ctcLogitsOutput = outputValues.first, let ctcLogits = ctcLogitsOutput else {
            throw VideoProcessingError.transcriptionFailed("无法获取 ctc_logits 输出结果")
        }
        
        // 获取 encoder_out_lens（实际序列长度）
        var actualSequenceLength: Int? = nil
        if outputValues.count > 1, let encoderOutLensOutput = outputValues[1] {
            actualSequenceLength = try extractSequenceLength(from: encoderOutLensOutput, api: api)
            #if DEBUG
            print("encoder_out_lens: \(actualSequenceLength ?? -1)")
            #endif
        }
        
        // 从 CTC logits 解码 token IDs
        let tokenIDs = try decodeCTCLogits(from: ctcLogits, actualLength: actualSequenceLength, api: api)
        
        #if DEBUG
        print("ONNX Runtime CTC 解码后的 token IDs: \(tokenIDs.prefix(20))... (共 \(tokenIDs.count) 个)")
        #endif
        
        return tokenIDs
    }
    
    /// 提取 encoder_out_lens（实际序列长度）
    private func extractSequenceLength(from outputValue: OpaquePointer, api: UnsafePointer<OrtApi>) throws -> Int {
        var tensorInfo: OpaquePointer?
        var status = api.pointee.GetTensorTypeAndShape(outputValue, &tensorInfo)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取 encoder_out_lens 张量信息: \(errorMsg)")
        }
        
        defer {
            if let info = tensorInfo {
                api.pointee.ReleaseTensorTypeAndShapeInfo(info)
            }
        }
        
        var dataPtr: UnsafeMutableRawPointer?
        status = api.pointee.GetTensorMutableData(outputValue, &dataPtr)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取 encoder_out_lens 数据: \(errorMsg)")
        }
        
        guard let data = dataPtr else {
            throw VideoProcessingError.transcriptionFailed("encoder_out_lens 数据为空")
        }
        
        // encoder_out_lens 通常是 Int32 或 Int64
        var elementType: ONNXTensorElementDataType = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
        status = api.pointee.GetTensorElementType(tensorInfo, &elementType)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取 encoder_out_lens 元素类型: \(errorMsg)")
        }
        
        if elementType == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32 {
            let int32Ptr = data.assumingMemoryBound(to: Int32.self)
            return Int(int32Ptr[0])
        } else if elementType == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64 {
            let int64Ptr = data.assumingMemoryBound(to: Int64.self)
            return Int(int64Ptr[0])
        } else {
            throw VideoProcessingError.transcriptionFailed("不支持的 encoder_out_lens 类型: \(elementType)")
        }
    }
    
    /// CTC 解码：从 CTC logits 解码 token IDs
    /// CTC 解码步骤：
    /// 1. 对每个时间步执行 argmax 获取最可能的 token
    /// 2. 移除 blank token（通常是 0）
    /// 3. 移除连续重复的 token（CTC 去重）
    private func decodeCTCLogits(from outputValue: OpaquePointer, actualLength: Int?, api: UnsafePointer<OrtApi>) throws -> [Int] {
        // 获取张量信息
        var tensorInfo: OpaquePointer?
        var status = api.pointee.GetTensorTypeAndShape(outputValue, &tensorInfo)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取 CTC logits 张量信息: \(errorMsg)")
        }
        
        defer {
            if let info = tensorInfo {
                api.pointee.ReleaseTensorTypeAndShapeInfo(info)
            }
        }
        
        // 获取元素类型（应该是 FLOAT）
        var elementType: ONNXTensorElementDataType = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
        status = api.pointee.GetTensorElementType(tensorInfo, &elementType)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取元素类型: \(errorMsg)")
        }
        
        guard elementType == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT else {
            throw VideoProcessingError.transcriptionFailed("CTC logits 应该是 FLOAT 类型，实际是: \(elementType)")
        }
        
        // 获取张量形状
        var dimCount: size_t = 0
        status = api.pointee.GetDimensionsCount(tensorInfo, &dimCount)
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取维度数量: \(errorMsg)")
        }
        
        var dims: [Int64] = Array(repeating: 0, count: Int(dimCount))
        status = api.pointee.GetDimensions(tensorInfo, &dims, dimCount)
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取维度: \(errorMsg)")
        }
        
        // CTC logits 形状应该是 [batch_size, sequence_length, vocab_size]
        guard dims.count == 3 else {
            throw VideoProcessingError.transcriptionFailed("CTC logits 应该是 3D 张量，实际维度: \(dims.count)")
        }
        
        let batchSize = Int(dims[0])
        let sequenceLength = actualLength ?? Int(dims[1])  // 使用实际长度（如果有）
        let vocabSize = Int(dims[2])
        
        #if DEBUG
        print("CTC logits 形状: batch=\(batchSize), sequence=\(sequenceLength), vocab=\(vocabSize)")
        #endif
        
        // 获取数据
        var dataPtr: UnsafeMutableRawPointer?
        status = api.pointee.GetTensorMutableData(outputValue, &dataPtr)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取 CTC logits 数据: \(errorMsg)")
        }
        
        guard let data = dataPtr else {
            throw VideoProcessingError.transcriptionFailed("CTC logits 数据为空")
        }
        
        let floatPtr = data.assumingMemoryBound(to: Float.self)
        
        // CTC Greedy Decoding
        // 注意：blank token 可能是 0（<unk>），也可能是其他值
        // 在 SenseVoice 中，blank token 通常是 0，但我们需要验证
        var tokenIDs: [Int] = []
        var allArgmaxResults: [Int] = []  // 用于调试：记录所有时间步的 argmax
        
        // 先收集所有时间步的 argmax 结果
        for t in 0..<sequenceLength {
            var maxValue: Float = -Float.infinity
            var maxIndex: Int = 0
            
            // 在当前时间步的所有词汇中查找最大值
            let startIdx = t * vocabSize
            let endIdx = startIdx + vocabSize
            
            for i in startIdx..<endIdx {
                let value = floatPtr[i]
                if value > maxValue {
                    maxValue = value
                    maxIndex = i - startIdx
                }
            }
            
            allArgmaxResults.append(maxIndex)
            
            // 先添加所有非 0 的 token（0 可能是 blank 或 <unk>）
            // 注意：如果 0 是 blank，我们需要过滤它；如果 0 是 <unk>，我们也应该过滤它
            if maxIndex != 0 {
                tokenIDs.append(maxIndex)
            }
        }
        
        #if DEBUG
        // 统计 argmax 结果的分布
        var tokenCounts: [Int: Int] = [:]
        for tokenID in allArgmaxResults {
            tokenCounts[tokenID, default: 0] += 1
        }
        let topTokens = tokenCounts.sorted { $0.value > $1.value }.prefix(10)
        print("CTC argmax 结果统计（前10个最常见的 token）:")
        for (tokenID, count) in topTokens {
            print("  Token \(tokenID): \(count) 次")
        }
        print("非 0 token 数量: \(tokenIDs.count)")
        #endif
        
        // CTC 去重：移除连续重复的 token
        var deduplicatedTokens: [Int] = []
        var prevToken: Int? = nil
        for token in tokenIDs {
            if token != prevToken {
                deduplicatedTokens.append(token)
                prevToken = token
            }
        }
        
        #if DEBUG
        print("CTC 去重后 token 数量: \(deduplicatedTokens.count)")
        #endif
        
        return deduplicatedTokens
    }
    
    private func extractTokenIDs(from outputValue: OpaquePointer, api: UnsafePointer<OrtApi>) throws -> [Int] {
        // 获取张量信息
        var tensorInfo: OpaquePointer?
        var status = api.pointee.GetTensorTypeAndShape(outputValue, &tensorInfo)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取张量信息: \(errorMsg)")
        }
        
        defer {
            if let info = tensorInfo {
                api.pointee.ReleaseTensorTypeAndShapeInfo(info)
            }
        }
        
        // 获取元素类型
        var elementType: ONNXTensorElementDataType = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
        status = api.pointee.GetTensorElementType(tensorInfo, &elementType)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取元素类型: \(errorMsg)")
        }
        
        // 获取元素数量
        var elementCount: size_t = 0
        status = api.pointee.GetTensorShapeElementCount(tensorInfo, &elementCount)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取元素数量: \(errorMsg)")
        }
        
        // 获取数据
        var dataPtr: UnsafeMutableRawPointer?
        status = api.pointee.GetTensorMutableData(outputValue, &dataPtr)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取张量数据: \(errorMsg)")
        }
        
        guard let data = dataPtr else {
            throw VideoProcessingError.transcriptionFailed("张量数据为空")
        }
        
        // 提取 token IDs
        var tokenIDs: [Int] = []
        
        if elementType == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64 {
            let int64Ptr = data.assumingMemoryBound(to: Int64.self)
            for i in 0..<elementCount {
                tokenIDs.append(Int(int64Ptr[i]))
            }
        } else if elementType == ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32 {
            let int32Ptr = data.assumingMemoryBound(to: Int32.self)
            for i in 0..<elementCount {
                tokenIDs.append(Int(int32Ptr[i]))
            }
        } else if elementType == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT {
            // CTC logits 输出：形状为 [batch_size, sequence_length, vocab_size]
            // 需要对每个时间步执行 argmax 操作
            let floatPtr = data.assumingMemoryBound(to: Float.self)
            
            // 获取张量形状
            var dimCount: size_t = 0
            status = api.pointee.GetDimensionsCount(tensorInfo, &dimCount)
            if status != nil {
                let errorMsg = getErrorMessage(from: status, api: api)
                api.pointee.ReleaseStatus(status)
                throw VideoProcessingError.transcriptionFailed("无法获取维度数量: \(errorMsg)")
            }
            
            var dims: [Int64] = Array(repeating: 0, count: Int(dimCount))
            status = api.pointee.GetDimensions(tensorInfo, &dims, dimCount)
            if status != nil {
                let errorMsg = getErrorMessage(from: status, api: api)
                api.pointee.ReleaseStatus(status)
                throw VideoProcessingError.transcriptionFailed("无法获取维度: \(errorMsg)")
            }
            
            // 假设形状为 [batch_size, sequence_length, vocab_size]
            // 对于 batch_size=1，跳过第一个维度
            let batchSize = dims.count > 0 ? Int(dims[0]) : 1
            let sequenceLength = dims.count > 1 ? Int(dims[1]) : Int(elementCount)
            let vocabSize = dims.count > 2 ? Int(dims[2]) : 1
            
            // 对每个时间步执行 argmax
            for t in 0..<sequenceLength {
                var maxValue: Float = -Float.infinity
                var maxIndex: Int = 0
                
                // 在当前时间步的所有词汇中查找最大值
                let startIdx = t * vocabSize
                let endIdx = startIdx + vocabSize
                
                for i in startIdx..<endIdx {
                    if i < elementCount {
                        let value = floatPtr[i]
                        if value > maxValue {
                            maxValue = value
                            maxIndex = i - startIdx
                        }
                    }
                }
                
                tokenIDs.append(maxIndex)
            }
        } else {
            throw VideoProcessingError.transcriptionFailed("不支持的输出类型: \(elementType) (rawValue: \(elementType.rawValue))")
        }
        
        return tokenIDs
    }
    
    /// 获取模型的输入输出名称
    private func getModelInputOutputNames(session: OpaquePointer, api: UnsafePointer<OrtApi>) throws -> ([String], [String]) {
        // 创建默认分配器
        var allocatorPtr: UnsafeMutablePointer<OrtAllocator>?
        var status = api.pointee.GetAllocatorWithDefaultOptions(&allocatorPtr)
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.modelLoadFailed("无法创建分配器: \(errorMsg)")
        }
        
        guard allocatorPtr != nil else {
            throw VideoProcessingError.modelLoadFailed("分配器为空")
        }
        
        // 获取输入数量
        var inputCount: size_t = 0
        status = api.pointee.SessionGetInputCount(session, &inputCount)
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.modelLoadFailed("无法获取输入数量: \(errorMsg)")
        }
        
        // 获取输出数量
        var outputCount: size_t = 0
        status = api.pointee.SessionGetOutputCount(session, &outputCount)
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.modelLoadFailed("无法获取输出数量: \(errorMsg)")
        }
        
        // 获取输入名称
        var inputNames: [String] = []
        for i in 0..<inputCount {
            var namePtr: UnsafeMutablePointer<CChar>?
            status = api.pointee.SessionGetInputName(session, i, allocatorPtr, &namePtr)
            if status != nil {
                let errorMsg = getErrorMessage(from: status, api: api)
                api.pointee.ReleaseStatus(status)
                throw VideoProcessingError.modelLoadFailed("无法获取输入名称 \(i): \(errorMsg)")
            }
            
            if let name = namePtr {
                inputNames.append(String(cString: name))
                // 释放分配的内存
                _ = api.pointee.AllocatorFree(allocatorPtr, namePtr)
            }
        }
        
        // 获取输出名称
        var outputNames: [String] = []
        for i in 0..<outputCount {
            var namePtr: UnsafeMutablePointer<CChar>?
            status = api.pointee.SessionGetOutputName(session, i, allocatorPtr, &namePtr)
            if status != nil {
                let errorMsg = getErrorMessage(from: status, api: api)
                api.pointee.ReleaseStatus(status)
                throw VideoProcessingError.modelLoadFailed("无法获取输出名称 \(i): \(errorMsg)")
            }
            
            if let name = namePtr {
                outputNames.append(String(cString: name))
                // 释放分配的内存
                _ = api.pointee.AllocatorFree(allocatorPtr, namePtr)
            }
        }
        
        return (inputNames, outputNames)
    }
    
    private func getErrorMessage(from status: OpaquePointer?, api: UnsafePointer<OrtApi>) -> String {
        guard let status = status else {
            return "未知错误"
        }
        
        let errorMsg = api.pointee.GetErrorMessage(status)
        return errorMsg.map { String(cString: $0) } ?? "未知错误"
    }
    
    deinit {
        if let api = api {
            if let session = session {
                api.pointee.ReleaseSession(session)
            }
            if let env = env {
                api.pointee.ReleaseEnv(env)
            }
        }
    }
}
