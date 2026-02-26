#!/usr/bin/env python3
"""
妙打 (FastV) Python 集成示例
============================

展示如何通过 Python 使用 AppleScript 控制 FastV 邮件应用。
适用于 AI 应用、自动化工具等场景。

使用方法：
    1. 确保 FastV 应用已安装并运行
    2. 安装依赖: pip install pyapplescript
    3. 运行: python python_fastv_example.py

注意：此脚本仅在 macOS 上可用
"""

import sys
from datetime import datetime

try:
    from appscript import app, k, mactypes, its
except ImportError:
    print("错误: 需要安装 appscript 库")
    print("请运行: pip install appscript")
    sys.exit(1)


class FastVClient:
    """FastV 邮件应用的 Python 客户端"""

    def __init__(self):
        """初始化 FastV 应用连接"""
        self.fastv = app('FastV')

    def get_accounts(self):
        """获取所有邮件账户"""
        try:
            accounts = self.fastv.accounts.get()
            result = []
            for account in accounts:
                result.append({
                    'id': account.id.get(),
                    'name': account.name.get(),
                    'email': account.email_address.get(),
                    'service_type': account.service_type.get(),
                    'is_enabled': account.is_enabled.get(),
                    'is_default': account.is_default.get(),
                    'connection_status': account.connection_status.get()
                })
            return result
        except Exception as e:
            print(f"获取账户失败: {e}")
            return []

    def get_default_account(self):
        """获取默认账户"""
        try:
            account = self.fastv.default_account.get()
            return {
                'id': account.id.get(),
                'name': account.name.get(),
                'email': account.email_address.get()
            }
        except Exception as e:
            print(f"获取默认账户失败: {e}")
            return None

    def get_folders(self, account_name=None):
        """获取文件夹列表"""
        try:
            if account_name:
                accounts = self.fastv.accounts[its.name == account_name]
                if not accounts:
                    print(f"未找到账户: {account_name}")
                    return []
                account = accounts[0]
            else:
                account = self.fastv.default_account.get()

            folders = account.folders.get()
            result = []
            for folder in folders:
                result.append({
                    'id': folder.id.get(),
                    'name': folder.name.get(),
                    'type': folder.folder_type.get(),
                    'unread_count': folder.unread_count.get(),
                    'total_count': folder.total_count.get()
                })
            return result
        except Exception as e:
            print(f"获取文件夹失败: {e}")
            return []

    def get_messages(self, folder_name='INBOX', limit=10, unread_only=False):
        """获取邮件列表"""
        try:
            account = self.fastv.default_account.get()
            folders = account.folders[its.name == folder_name]

            if not folders:
                # 尝试按类型查找
                folders = account.folders[its.folder_type == folder_name.lower()]

            if not folders:
                print(f"未找到文件夹: {folder_name}")
                return []

            folder = folders[0]
            messages = folder.mail_messages.get()

            # 过滤未读
            if unread_only:
                messages = [m for m in messages if not m.is_read.get()]

            # 限制数量
            messages = messages[:limit]

            result = []
            for msg in messages:
                result.append({
                    'id': msg.id.get(),
                    'subject': msg.subject.get(),
                    'from': msg.from.get(),
                    'from_address': msg.from_address.get(),
                    'to': msg.to.get(),
                    'date': msg.date_sent.get(),
                    'is_read': msg.is_read.get(),
                    'is_starred': msg.is_starred.get(),
                    'has_attachments': msg.has_attachments.get(),
                    'preview': msg.preview.get()
                })
            return result
        except Exception as e:
            print(f"获取邮件失败: {e}")
            return []

    def get_message_body(self, message_index=0, folder_name='INBOX'):
        """获取邮件正文"""
        try:
            account = self.fastv.default_account.get()
            folders = account.folders[its.name == folder_name]
            if not folders:
                folders = account.folders[its.folder_type == folder_name.lower()]

            if not folders:
                print(f"未找到文件夹: {folder_name}")
                return None

            folder = folders[0]
            messages = folder.mail_messages.get()

            if message_index >= len(messages):
                print(f"邮件索引超出范围: {message_index}")
                return None

            msg = messages[message_index]

            # 获取正文
            text_body = msg.text_body.get() if hasattr(msg, 'text_body') else None
            html_body = msg.html_body.get() if hasattr(msg, 'html_body') else None

            return {
                'subject': msg.subject.get(),
                'from': msg.from.get(),
                'to': msg.to.get(),
                'text_body': text_body,
                'html_body': html_body
            }
        except Exception as e:
            print(f"获取邮件正文失败: {e}")
            return None

    def create_draft(self, to_address, subject, body, cc=None, bcc=None):
        """创建邮件草稿"""
        try:
            params = {
                'to': to_address,
                'subject': subject,
                'body': body,
                'save_as_draft': True
            }

            if cc:
                params['cc'] = cc
            if bcc:
                params['bcc'] = bcc

            self.fastv.create_mail(**params)
            print("✅ 草稿已创建")
            return True
        except Exception as e:
            print(f"创建草稿失败: {e}")
            return False

    def send_mail(self, to_address, subject, body):
        """发送邮件"""
        try:
            self.fastv.create_mail(
                to=to_address,
                subject=subject,
                body=body,
                save_as_draft=False
            )
            print("✅ 邮件已发送")
            return True
        except Exception as e:
            print(f"发送邮件失败: {e}")
            return False

    def mark_as_read(self, message_index=0, folder_name='INBOX'):
        """标记邮件为已读"""
        try:
            account = self.fastv.default_account.get()
            folders = account.folders[its.name == folder_name]
            if not folders:
                folders = account.folders[its.folder_type == folder_name.lower()]

            if not folders:
                print(f"未找到文件夹: {folder_name}")
                return False

            folder = folders[0]
            messages = folder.mail_messages.get()

            if message_index >= len(messages):
                print(f"邮件索引超出范围: {message_index}")
                return False

            msg = messages[message_index]
            msg.mark_as_read()
            print(f"✅ 已标记邮件为已读: {msg.subject.get()}")
            return True
        except Exception as e:
            print(f"标记已读失败: {e}")
            return False

    def sync_account(self, folder_name=None):
        """同步账户"""
        try:
            account = self.fastv.default_account.get()
            if folder_name:
                account.sync(folder=folder_name)
            else:
                account.sync()
            print("✅ 同步已启动")
            return True
        except Exception as e:
            print(f"同步失败: {e}")
            return False


def main():
    """示例使用"""
    print("=" * 60)
    print("妙打 (FastV) Python 集成示例")
    print("=" * 60)
    print()

    # 创建客户端
    client = FastVClient()

    # 1. 获取账户列表
    print("1. 获取账户列表")
    print("-" * 60)
    accounts = client.get_accounts()
    if accounts:
        for acc in accounts:
            print(f"  账户: {acc['name']} ({acc['email']})")
            print(f"    类型: {acc['service_type']}, 默认: {acc['is_default']}")
    else:
        print("  未找到账户，请先在 FastV 应用中添加邮件账户")
    print()

    # 2. 获取文件夹列表
    print("2. 获取文件夹列表")
    print("-" * 60)
    folders = client.get_folders()
    if folders:
        for folder in folders:
            print(f"  {folder['name']}: 未读 {folder['unread_count']}, 总计 {folder['total_count']}")
    print()

    # 3. 获取最新邮件
    print("3. 获取最新 5 封邮件")
    print("-" * 60)
    messages = client.get_messages(limit=5)
    if messages:
        for i, msg in enumerate(messages, 1):
            print(f"  {i}. {msg['subject']}")
            print(f"     来自: {msg['from']}")
            print(f"     日期: {msg['date']}")
            print(f"     已读: {msg['is_read']}")
            print()
    else:
        print("  未找到邮件")
    print()

    # 4. 获取未读邮件
    print("4. 获取未读邮件")
    print("-" * 60)
    unread_messages = client.get_messages(unread_only=True)
    if unread_messages:
        print(f"  未读邮件数量: {len(unread_messages)}")
        for msg in unread_messages[:3]:  # 只显示前3封
            print(f"  - {msg['subject']} ({msg['from']})")
    else:
        print("  没有未读邮件")
    print()

    # 5. 创建草稿（示例，注释掉以避免实际创建）
    # print("5. 创建草稿（示例）")
    # print("-" * 60)
    # client.create_draft(
    #     to_address="recipient@example.com",
    #     subject="测试邮件",
    #     body="这是一封测试邮件"
    # )
    # print()

    print("=" * 60)
    print("示例完成")
    print("=" * 60)


if __name__ == "__main__":
    main()
