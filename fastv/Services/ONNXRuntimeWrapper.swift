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
        let logid = "typecho".cString(using: .utf8)
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
        
        // 性能优化：设置多线程
        let numThreads = max(4, ProcessInfo.processInfo.activeProcessorCount)
        status = api.pointee.SetIntraOpNumThreads(sessionOptions, Int32(numThreads))
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            print("⚠️ 设置线程数失败: \(errorMsg)")
        } else {
            print("✅ ONNX Runtime 使用 \(numThreads) 个线程")
        }
        
        // 设置图优化级别
        status = api.pointee.SetSessionGraphOptimizationLevel(sessionOptions, ORT_ENABLE_ALL)
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            print("⚠️ 设置图优化级别失败: \(errorMsg)")
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
    
    /// 运行图像推理（通用 4D 张量输入）
    /// - Parameters:
    ///   - inputData: 展平的输入数据 (Float32)
    ///   - inputShape: 输入形状 [N, C, H, W]
    ///   - outputShape: 期望的输出形状 [N, C, H, W]
    /// - Returns: 展平的输出数据
    func runImageInference(inputData: [Float], inputShape: [Int], outputShape: [Int]) throws -> [Float] {
        guard let api = api else {
            throw VideoProcessingError.modelLoadFailed("API 未初始化")
        }
        
        guard let session = session else {
            throw VideoProcessingError.modelLoadFailed("会话未创建，请先加载模型")
        }
        
        // 1. 准备内存信息
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
        defer { if let info = memoryInfo { api.pointee.ReleaseMemoryInfo(info) } }
        
        // 2. 创建输入张量
        let inputShapeInt64 = inputShape.map { Int64($0) }
        var inputTensor: OpaquePointer?
        
        // 创建可变的数据副本
        var inputDataCopy = inputData
        
        status = inputDataCopy.withUnsafeMutableBytes { bytes -> OpaquePointer? in
            return api.pointee.CreateTensorWithDataAsOrtValue(
                memoryInfo,
                bytes.baseAddress!,
                inputData.count * MemoryLayout<Float>.size,
                inputShapeInt64,
                inputShapeInt64.count,
                ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
                &inputTensor
            )
        }
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法创建输入张量: \(errorMsg)")
        }
        defer { if let tensor = inputTensor { api.pointee.ReleaseValue(tensor) } }
        
        // 3. 准备输入/输出名称
        // 注意：这里假设模型只有一个输入和一个输出，或者我们使用默认名称
        // 为了通用性，应该从会话中获取名称，但简化起见，我们尝试使用硬编码或获取索引0
        
        // 获取输入名称
        var inputName: UnsafeMutablePointer<CChar>?
        var allocator: UnsafeMutablePointer<OrtAllocator>?
        api.pointee.GetAllocatorWithDefaultOptions(&allocator)
        
        status = api.pointee.SessionGetInputName(session, 0, allocator, &inputName)
        if status != nil {
            // 如果获取失败，尝试使用常见名称
            let errorMsg = getErrorMessage(from: status, api: api)
            print("警告: 无法获取输入名称: \(errorMsg)")
            api.pointee.ReleaseStatus(status)
        }
        
        // 获取输出名称
        var outputName: UnsafeMutablePointer<CChar>?
        status = api.pointee.SessionGetOutputName(session, 0, allocator, &outputName)
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            print("警告: 无法获取输出名称: \(errorMsg)")
            api.pointee.ReleaseStatus(status)
        }
        
        let inputNameStr = inputName != nil ? String(cString: inputName!) : "input_1"
        let outputNameStr = outputName != nil ? String(cString: outputName!) : "output_1"
        
        // 4. 运行推理
        var outputTensor: OpaquePointer?
        let inputNames = [inputNameStr]
        let outputNames = [outputNameStr]
        
        // 创建 C 字符串指针数组
        let inputNameCStrings = inputNames.map { $0.cString(using: .utf8)! }
        let outputNameCStrings = outputNames.map { $0.cString(using: .utf8)! }
        
        // 需要构建指针数组
        var inputTensors = [inputTensor]
        
        // 使用 withExtendedLifetime 确保字符串在整个调用期间有效
        let runStatus = withExtendedLifetime((inputNameCStrings, outputNameCStrings)) {
            // 创建指向 C 字符串指针的指针数组
            var inputNamePtrs: [UnsafePointer<CChar>?] = inputNameCStrings.map { UnsafePointer($0) }
            var outputNamePtrs: [UnsafePointer<CChar>?] = outputNameCStrings.map { UnsafePointer($0) }
            
            return api.pointee.Run(
                session,
                nil, // run options
                &inputNamePtrs,
                inputTensors.withUnsafeBufferPointer { $0.baseAddress },
                1, // input count
                &outputNamePtrs,
                1, // output count
                &outputTensor
            )
        }
        
        if runStatus != nil {
            let errorMsg = getErrorMessage(from: runStatus, api: api)
            api.pointee.ReleaseStatus(runStatus)
            throw VideoProcessingError.transcriptionFailed("推理运行失败: \(errorMsg)")
        }
        defer { if let tensor = outputTensor { api.pointee.ReleaseValue(tensor) } }
        
        // 5. 获取输出数据
        var outputDataPtr: UnsafeMutableRawPointer?
        status = api.pointee.GetTensorMutableData(outputTensor, &outputDataPtr)
        
        if status != nil {
            let errorMsg = getErrorMessage(from: status, api: api)
            api.pointee.ReleaseStatus(status)
            throw VideoProcessingError.transcriptionFailed("无法获取输出数据: \(errorMsg)")
        }
        
        // 复制数据到 Swift 数组
        let count = outputShape.reduce(1, *)
        let outputBuffer = outputDataPtr!.bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: outputBuffer, count: count))
    }
    
    func runInference(input: [[[Float]]], language: TranscriptLanguage = .auto, enableCTCDeduplication: Bool = false) throws -> [Int] {
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
        // 关键：必须按照模型定义的输入名称顺序创建张量，确保 inputTensors 和 inputNameStrings 的顺序完全一致
        var inputTensors: [OpaquePointer?] = []
        var inputNameStrings: [String] = []
        
        // 按照模型定义的顺序创建输入：speech, speech_lengths, language, textnorm
        // 注意：ONNX Runtime 的 Run API 使用名称匹配，所以顺序不重要，但为了调试方便，我们按照固定顺序创建
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
            if let index = inputNames.firstIndex(of: "speech_lengths") {
                inputNameStrings.append(inputNames[index])
            } else if inputNames.count > 1 {
                inputNameStrings.append(inputNames[1])
            }
        }
        
        // 3. language 输入（语言标识）
        // SenseVoice lid_dict: {"auto": 0, "zh": 3, "en": 4, "yue": 7, "ja": 11, "ko": 12, "nospeech": 13}
        var languageTensor: OpaquePointer?
        let languageDataValue: Int32 = language.languageID
        let languageData: [Int32] = [languageDataValue]
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
            print("language 参数: \(languageDataValue)")
            #endif
        }
        
        // 4. textnorm 输入（文本规范化）
        // textnormDict = { "withitn": 14, "woitn": 15 }
        var textnormTensor: OpaquePointer?
        let textnormDataValue: Int32 = 14 // 14 = withitn (with ITN，包含标点符号)
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
            // 清理额外的输入张量（除了 speech 张量，它会在上面的 defer 中释放）
            // 释放所有不是 inputTensor 的张量
            for tensor in inputTensors {
                if let tensor = tensor, tensor != inputTensor {
                    api.pointee.ReleaseValue(tensor)
                }
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
        
        // 为每个输入名称创建 C 字符串（使用 withCString 确保生命周期）
        var inputNamePtrs: [UnsafePointer<CChar>?] = []
        
        // 使用 withExtendedLifetime 确保所有字符串在整个函数调用期间有效
        let inputNameCStrings = inputNameStrings.map { $0.cString(using: .utf8)! }
        inputNamePtrs = inputNameCStrings.map { UnsafePointer($0) }
        
        #if DEBUG
        // 验证输入顺序一致性
        print("验证输入顺序一致性:")
        for (index, (name, tensor)) in zip(inputNameStrings, inputTensors).enumerated() {
            print("  输入[\(index)]: name=\(name), tensor=\(tensor != nil ? "有效" : "nil")")
        }
        #endif
        
        print("🔄 开始 ONNX 推理... (输入: \(sequenceLength) 帧，这可能需要一些时间)")
        let inferenceStartTime = CFAbsoluteTimeGetCurrent()
        
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
        
        let inferenceEndTime = CFAbsoluteTimeGetCurrent()
        let inferenceDuration = inferenceEndTime - inferenceStartTime
        print("✅ ONNX 推理完成，耗时: \(String(format: "%.2f", inferenceDuration)) 秒")
        
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
        let tokenIDs = try decodeCTCLogits(from: ctcLogits, actualLength: actualSequenceLength, api: api, enableDeduplication: enableCTCDeduplication)
        
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
    private func decodeCTCLogits(from outputValue: OpaquePointer, actualLength: Int?, api: UnsafePointer<OrtApi>, enableDeduplication: Bool = false) throws -> [Int] {
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
        
        // CTC 去重：移除连续重复的 token（可选）
        // 注意：禁用去重可以保留叠词（如"谢谢"）和连续数字（如"100"中的"00"）
        if enableDeduplication {
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
        } else {
            #if DEBUG
            print("CTC 去重已禁用，保留所有 token")
            #endif
            
            return tokenIDs
        }
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
            _ = dims.count > 0 ? Int(dims[0]) : 1
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
