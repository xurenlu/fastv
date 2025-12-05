//
//  EmailSignatureTemplates.swift
//  fastv
//
//  Created for Email Signature Templates
//

import Foundation

/// 邮件签名模板
struct EmailSignatureTemplate: Identifiable {
    let id: String
    let name: String
    let description: String
    let content: String
    let isHtml: Bool
    
    /// 从模板创建签名内容（替换变量占位符）
    func createContent(name: String, email: String) -> String {
        var result = content
        result = result.replacingOccurrences(of: "{{name}}", with: name)
        result = result.replacingOccurrences(of: "{{email}}", with: email)
        return result
    }
}

/// 邮件签名模板服务
class EmailSignatureTemplates {
    static let shared = EmailSignatureTemplates()
    
    /// 所有可用的签名模板
    var templates: [EmailSignatureTemplate] {
        return [
            // 简洁风格
            classicTemplate,
            minimalTemplate,
            cleanTemplate,
            
            // 商务风格
            businessFullTemplate,
            corporateTemplate,
            executiveTemplate,
            
            // 创意风格
            modernTemplate,
            creativeTemplate,
            
            // 纯文本风格
            plainTextSimpleTemplate,
            plainTextBusinessTemplate,
            plainTextMinimalTemplate
        ]
    }
    
    private init() {}
    
    // MARK: - 基础样式常量
    
    private let baseFont = "font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;"
    private let serifFont = "font-family: Georgia, 'Times New Roman', Times, serif;"
    
    // MARK: - 简洁风格模板
    
    /// 经典模板 - 稳健的表格布局
    private var classicTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "classic",
            name: "经典",
            description: "最兼容的经典设计，适合任何场合",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 14px; color: #333333; line-height: 1.5;">
                <tr>
                    <td style="padding-top: 10px; border-top: 1px solid #e5e5e5;">
                        <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td style="padding-bottom: 4px;">
                                    <span style="font-weight: bold; font-size: 16px; color: #000000;">{{name}}</span>
                                </td>
                            </tr>
                            <tr>
                                <td style="color: #666666;">
                                    <a href="mailto:{{email}}" style="color: #0071e3; text-decoration: none;">{{email}}</a>
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </table>
            """,
            isHtml: true
        )
    }
    
    /// 极简模板 - 无边框，纯净
    private var minimalTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "minimal",
            name: "极简",
            description: "无多余装饰，极致简约",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 14px; line-height: 1.4;">
                <tr>
                    <td style="padding-right: 10px; border-right: 1px solid #cccccc;">
                        <span style="font-weight: 600; color: #333333;">{{name}}</span>
                    </td>
                    <td style="padding-left: 10px;">
                        <a href="mailto:{{email}}" style="color: #666666; text-decoration: none;">{{email}}</a>
                    </td>
                </tr>
            </table>
            """,
            isHtml: true
        )
    }
    
    /// 清爽模板 - 蓝色强调色
    private var cleanTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "clean",
            name: "清爽",
            description: "带强调色的清爽设计",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 14px; color: #444444;">
                <tr>
                    <td width="3" style="background-color: #0071e3;"></td>
                    <td width="12"></td>
                    <td>
                        <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td style="font-size: 16px; font-weight: bold; color: #0071e3; padding-bottom: 2px;">{{name}}</td>
                            </tr>
                            <tr>
                                <td style="padding-bottom: 2px;">{{title}}</td>
                            </tr>
                            <tr>
                                <td>
                                    <a href="mailto:{{email}}" style="color: #666666; text-decoration: none;">{{email}}</a>
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </table>
            """,
            isHtml: true
        )
    }
    
    // MARK: - 商务风格模板
    
    /// 商务完整模板 - 包含所有信息
    private var businessFullTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "business_full",
            name: "商务完整",
            description: "标准商务布局，信息展示完整",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 13px; color: #444444; line-height: 1.4;">
                <tr>
                    <td style="padding-bottom: 8px; border-bottom: 1px solid #eeeeee;">
                        <span style="font-size: 18px; font-weight: bold; color: #222222;">{{name}}</span><br>
                        <span style="color: #666666;">{{title}}</span>
                    </td>
                </tr>
                <tr>
                    <td style="padding-top: 8px;">
                        <span style="font-weight: bold; color: #333333;">{{company}}</span>
                    </td>
                </tr>
                <tr>
                    <td style="padding-top: 4px;">
                        <span style="color: #0071e3;">✉️</span> <a href="mailto:{{email}}" style="color: #444444; text-decoration: none;">{{email}}</a>
                    </td>
                </tr>
                <tr>
                    <td style="padding-top: 2px;">
                        <span style="color: #0071e3;">📞</span> {{phone}}
                    </td>
                </tr>
                <tr>
                    <td style="padding-top: 2px;">
                        <span style="color: #0071e3;">🌐</span> <a href="{{website}}" style="color: #444444; text-decoration: none;">{{website}}</a>
                    </td>
                </tr>
                <tr>
                    <td style="padding-top: 2px;">
                        <span style="color: #0071e3;">📍</span> {{address}}
                    </td>
                </tr>
            </table>
            """,
            isHtml: true
        )
    }
    
    /// 企业模板 - 双列布局
    private var corporateTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "corporate",
            name: "企业双列",
            description: "左右分栏的专业布局",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 13px; color: #555555;">
                <tr>
                    <td valign="top" style="padding-right: 20px; border-right: 1px solid #dddddd;">
                        <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td style="font-size: 18px; font-weight: bold; color: #1a1a1a; padding-bottom: 4px;">{{name}}</td>
                            </tr>
                            <tr>
                                <td style="color: #0071e3; font-weight: 500; padding-bottom: 4px;">{{title}}</td>
                            </tr>
                            <tr>
                                <td style="font-size: 12px; color: #888888;">{{company}}</td>
                            </tr>
                        </table>
                    </td>
                    <td valign="top" style="padding-left: 20px;">
                        <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td style="padding-bottom: 4px;">
                                    <span style="color: #0071e3; margin-right: 5px;">E:</span>
                                    <a href="mailto:{{email}}" style="color: #555555; text-decoration: none;">{{email}}</a>
                                </td>
                            </tr>
                            <tr>
                                <td style="padding-bottom: 4px;">
                                    <span style="color: #0071e3; margin-right: 5px;">P:</span>
                                    {{phone}}
                                </td>
                            </tr>
                            <tr>
                                <td style="padding-bottom: 4px;">
                                    <span style="color: #0071e3; margin-right: 5px;">W:</span>
                                    <a href="{{website}}" style="color: #555555; text-decoration: none;">{{website}}</a>
                                </td>
                            </tr>
                            <tr>
                                <td>
                                    <span style="color: #0071e3; margin-right: 5px;">A:</span>
                                    {{address}}
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </table>
            """,
            isHtml: true
        )
    }
    
    /// 高管模板 - 衬线字体
    private var executiveTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "executive",
            name: "高管",
            description: "使用衬线字体的传统权威风格",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(serifFont) font-size: 14px; color: #222222;">
                <tr>
                    <td>
                        <span style="font-size: 20px; font-weight: bold; letter-spacing: 0.5px;">{{name}}</span>
                    </td>
                </tr>
                <tr>
                    <td style="padding-bottom: 12px; font-style: italic; color: #666666;">
                        {{title}} | {{company}}
                    </td>
                </tr>
                <tr>
                    <td style="border-top: 2px solid #222222; padding-top: 12px;">
                        <table cellpadding="0" cellspacing="0" border="0" style="font-size: 13px;">
                            <tr>
                                <td style="padding-right: 15px;">
                                    <a href="mailto:{{email}}" style="color: #222222; text-decoration: none;">{{email}}</a>
                                </td>
                                <td style="padding-right: 15px;">{{phone}}</td>
                                <td><a href="{{website}}" style="color: #222222; text-decoration: none;">{{website}}</a></td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </table>
            """,
            isHtml: true
        )
    }
    
    // MARK: - 创意风格模板
    
    /// 现代色块模板
    private var modernTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "modern",
            name: "现代色块",
            description: "使用背景色块的现代设计",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 14px;">
                <tr>
                    <td style="background-color: #f5f5f7; padding: 15px; border-radius: 4px;">
                        <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td style="font-weight: bold; font-size: 16px; color: #1d1d1f; padding-bottom: 4px;">{{name}}</td>
                            </tr>
                            <tr>
                                <td style="color: #0071e3; font-size: 13px; padding-bottom: 8px;">{{title}}</td>
                            </tr>
                            <tr>
                                <td style="font-size: 13px; color: #666666; line-height: 1.6;">
                                    <a href="mailto:{{email}}" style="color: #666666; text-decoration: none;">{{email}}</a><br>
                                    {{phone}}<br>
                                    <a href="{{website}}" style="color: #666666; text-decoration: none;">{{website}}</a>
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </table>
            """,
            isHtml: true
        )
    }
    
    /// 创意模板 - 底部边框
    private var creativeTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "creative",
            name: "创意",
            description: "底部彩色边框设计",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 14px; color: #333333;">
                <tr>
                    <td style="padding-bottom: 10px;">
                        <span style="font-size: 18px; font-weight: 800; color: #000000; letter-spacing: -0.5px;">{{name}}</span><br>
                        <span style="font-size: 13px; text-transform: uppercase; letter-spacing: 1px; color: #888888;">{{title}}</span>
                    </td>
                </tr>
                <tr>
                    <td style="padding: 10px 0; border-top: 4px solid #000000; border-bottom: 1px solid #eeeeee;">
                        <table cellpadding="0" cellspacing="0" border="0" style="font-size: 13px;">
                            <tr>
                                <td style="padding-right: 20px;">
                                    <span style="font-weight: bold;">E:</span> <a href="mailto:{{email}}" style="color: #333333; text-decoration: none;">{{email}}</a>
                                </td>
                                <td>
                                    <span style="font-weight: bold;">P:</span> {{phone}}
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>
            </table>
            """,
            isHtml: true
        )
    }
    
    // MARK: - 纯文本模板
    
    /// 简单纯文本模板
    private var plainTextSimpleTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "plain_simple",
            name: "纯文本-简单",
            description: "简洁的纯文本签名",
            content: """
            
            --
            {{name}}
            {{email}}
            """,
            isHtml: false
        )
    }
    
    /// 商务纯文本模板
    private var plainTextBusinessTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "plain_business",
            name: "纯文本-商务",
            description: "适合商务场合的纯文本签名",
            content: """
            
            --
            {{name}}
            {{title}} | {{company}}
            
            E: {{email}}
            P: {{phone}}
            W: {{website}}
            """,
            isHtml: false
        )
    }
    
    /// 极简纯文本模板
    private var plainTextMinimalTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "plain_minimal",
            name: "纯文本-极简",
            description: "最简洁的纯文本签名",
            content: """
            
            {{name}} | {{email}}
            """,
            isHtml: false
        )
    }
    
    /// 根据ID获取模板
    func getTemplate(id: String) -> EmailSignatureTemplate? {
        return templates.first { $0.id == id }
    }
}