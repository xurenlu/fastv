//
//  fastv-Bridging-Header.h
//  fastv
//
//  Created for LibEtPan integration
//

#ifndef fastv_Bridging_Header_h
#define fastv_Bridging_Header_h

// LibEtPan wrapper（Swift 通过桥接 LibEtPan C API，只需要通过 LibEtPanWrapper 访问）
// 路径相对于桥接头文件所在目录（fastv/）
#import "Services/LibEtPanWrapper.h"

// 注意：LibEtPan 的 C 头文件在 LibEtPanWrapper.m 中导入，不需要在这里导入
// Swift 不需要直接访问 C API，只需要通过 LibEtPanWrapper 的 Objective-C 接口

#endif /* fastv_Bridging_Header_h */

