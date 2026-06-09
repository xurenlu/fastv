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

            // 精致样式（v1.4.3-rc8 新增）
            brandCardTemplate,
            accentBarTemplate,
            warmAccentTemplate,
            gradientGlassTemplate,
            mondrianTemplate,
            monoChipTemplate,

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
    
    // MARK: - 精致样式模板（v1.4.3-rc8 新增）

    /// 品牌色卡片 - 圆角卡片 + 强调色名称
    private var brandCardTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "brand_card",
            name: "品牌卡片",
            description: "圆角卡片 + 品牌色名称，适合产品 / 设计岗",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 14px;">
                <tr>
                    <td style="padding: 16px 20px; background-color: #fafafa; border-radius: 10px; border: 1px solid #ececec;">
                        <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td style="padding-bottom: 6px;">
                                    <span style="font-size: 18px; font-weight: 700; color: #6E56CF; letter-spacing: -0.2px;">{{name}}</span>
                                    <span style="font-size: 13px; color: #6f6f76; padding-left: 6px;">· {{title}}</span>
                                </td>
                            </tr>
                            <tr>
                                <td style="font-size: 12px; color: #6f6f76; padding-bottom: 10px;">{{company}}</td>
                            </tr>
                            <tr>
                                <td style="font-size: 13px; color: #38383f; line-height: 1.7;">
                                    <a href="mailto:{{email}}" style="color: #6E56CF; text-decoration: none;">{{email}}</a>
                                    &nbsp;·&nbsp; {{phone}}
                                    &nbsp;·&nbsp; <a href="{{website}}" style="color: #38383f; text-decoration: none;">{{website}}</a>
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

    /// 左侧粗色条 - 强对比，名称突出
    private var accentBarTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "accent_bar",
            name: "左色条",
            description: "左侧粗色条 + 大字号名片，名字最先被看到",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 13px; color: #2f3137;">
                <tr>
                    <td width="6" style="background-color: #FF5A5F; border-radius: 3px;"></td>
                    <td width="16"></td>
                    <td>
                        <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td style="font-size: 22px; font-weight: 800; color: #1a1a1d; letter-spacing: -0.5px; padding-bottom: 2px;">{{name}}</td>
                            </tr>
                            <tr>
                                <td style="font-size: 12px; color: #FF5A5F; font-weight: 600; text-transform: uppercase; letter-spacing: 1.2px; padding-bottom: 10px;">{{title}} · {{company}}</td>
                            </tr>
                            <tr>
                                <td style="line-height: 1.7;">
                                    <a href="mailto:{{email}}" style="color: #2f3137; text-decoration: none;">✉ {{email}}</a><br>
                                    <span style="color: #2f3137;">☎ {{phone}}</span><br>
                                    <a href="{{website}}" style="color: #2f3137; text-decoration: none;">⌖ {{website}}</a>
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

    /// 暖色调 - 橙红渐变线条，温暖而不张扬
    private var warmAccentTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "warm_accent",
            name: "暖色线条",
            description: "橙红渐变下划线，适合自由职业 / 文创",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 13.5px; color: #3b2f2f;">
                <tr>
                    <td>
                        <span style="font-size: 17px; font-weight: 700; color: #2b1d1d;">{{name}}</span>
                        <span style="color: #b96a4a; font-style: italic; padding-left: 8px;">{{title}}</span>
                    </td>
                </tr>
                <tr>
                    <td style="padding: 6px 0 12px 0;">
                        <div style="height: 3px; width: 80px; background: linear-gradient(90deg, #FF8A65 0%, #FF5252 100%); border-radius: 2px;"></div>
                    </td>
                </tr>
                <tr>
                    <td style="line-height: 1.7;">
                        <a href="mailto:{{email}}" style="color: #b96a4a; text-decoration: none; font-weight: 600;">{{email}}</a>
                        <span style="color: #aaa; padding: 0 6px;">|</span>
                        <span>{{phone}}</span>
                    </td>
                </tr>
                <tr>
                    <td style="font-size: 12px; color: #8a7c7c; padding-top: 4px;">
                        <a href="{{website}}" style="color: #8a7c7c; text-decoration: none;">{{website}}</a>
                        <span style="padding: 0 6px;">·</span>
                        {{address}}
                    </td>
                </tr>
            </table>
            """,
            isHtml: true
        )
    }

    /// 渐变玻璃 - 浅紫淡蓝背景，现代轻盈
    private var gradientGlassTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "gradient_glass",
            name: "渐变玻璃",
            description: "浅紫淡蓝渐变背景，现代而轻盈",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 13px;">
                <tr>
                    <td style="padding: 18px 22px; background: linear-gradient(135deg, #e0c3fc 0%, #8ec5fc 100%); border-radius: 12px;">
                        <table cellpadding="0" cellspacing="0" border="0" style="width: 100%;">
                            <tr>
                                <td>
                                    <div style="font-size: 19px; font-weight: 700; color: #1a1a2e; padding-bottom: 2px;">{{name}}</div>
                                    <div style="font-size: 12px; color: #4a4a6a; padding-bottom: 12px;">{{title}} @ {{company}}</div>
                                    <div style="font-size: 12.5px; color: #1a1a2e; line-height: 1.7;">
                                        <a href="mailto:{{email}}" style="color: #1a1a2e; text-decoration: none;">{{email}}</a>
                                        &nbsp;·&nbsp; {{phone}}
                                        &nbsp;·&nbsp; <a href="{{website}}" style="color: #1a1a2e; text-decoration: none;">{{website}}</a>
                                    </div>
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

    /// 蒙德里安格 - 色块分割，平面设计感
    private var mondrianTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "mondrian",
            name: "蒙德里安",
            description: "色块分割排版，强平面设计感",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 13px; color: #1a1a1a;">
                <tr>
                    <td>
                        <table cellpadding="0" cellspacing="0" border="0">
                            <tr>
                                <td style="padding: 14px 16px; background-color: #0F62FE; vertical-align: top;">
                                    <div style="color: #ffffff; font-size: 18px; font-weight: 700; letter-spacing: -0.3px;">{{name}}</div>
                                    <div style="color: #c4dafe; font-size: 11.5px; padding-top: 4px;">{{title}}</div>
                                </td>
                                <td width="4" style="background-color: #FFFFFF;"></td>
                                <td style="padding: 14px 16px; background-color: #FAFAFA; vertical-align: top;">
                                    <div style="font-size: 12px; line-height: 1.7;">
                                        <span style="color: #888;">公司</span> &nbsp; {{company}}<br>
                                        <span style="color: #888;">邮箱</span> &nbsp; <a href="mailto:{{email}}" style="color: #0F62FE; text-decoration: none;">{{email}}</a><br>
                                        <span style="color: #888;">电话</span> &nbsp; {{phone}}
                                    </div>
                                </td>
                            </tr>
                            <tr><td colspan="3" style="height: 4px; background-color: #FFC832;"></td></tr>
                        </table>
                    </td>
                </tr>
            </table>
            """,
            isHtml: true
        )
    }

    /// 黑白胶囊 - 极简芯片化排版
    private var monoChipTemplate: EmailSignatureTemplate {
        EmailSignatureTemplate(
            id: "mono_chip",
            name: "黑白胶囊",
            description: "黑白胶囊芯片排版，极简且高级",
            content: """
            <br>
            <table cellpadding="0" cellspacing="0" border="0" style="\(baseFont) font-size: 13px; color: #111111;">
                <tr>
                    <td style="padding-bottom: 6px;">
                        <span style="font-size: 20px; font-weight: 800; letter-spacing: -0.4px;">{{name}}</span>
                        <span style="font-size: 12px; color: #6b6b6b; padding-left: 8px;">— {{title}}</span>
                    </td>
                </tr>
                <tr>
                    <td style="padding-bottom: 10px; font-size: 12px; color: #6b6b6b;">{{company}}</td>
                </tr>
                <tr>
                    <td style="font-size: 12px;">
                        <a href="mailto:{{email}}" style="display: inline-block; padding: 4px 10px; background-color: #111111; color: #ffffff; text-decoration: none; border-radius: 999px; margin-right: 6px;">{{email}}</a>
                        <span style="display: inline-block; padding: 4px 10px; background-color: #f1f1f1; color: #111111; border-radius: 999px; margin-right: 6px;">{{phone}}</span>
                        <a href="{{website}}" style="display: inline-block; padding: 4px 10px; background-color: #f1f1f1; color: #111111; text-decoration: none; border-radius: 999px;">{{website}}</a>
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