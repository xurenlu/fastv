#!/usr/bin/env ruby
# frozen_string_literal: true

# 把 QEchoIME 输入法 target 集成进 fastv.xcodeproj。
# 说明：本工程使用 Xcode 16 文件系统同步 group（fastv/ → musetype、fastvTests/ → fastvTests），
# 主 App 与测试的新增源文件自动入编，这里只需要：
#   1. 创建 QEchoIME app target 并配置构建设置
#   2. 挂 QEchoIME/ 下源文件 + 共享契约文件（fastv/Services/InputMethodBridgeContract.swift）
#   3. musetype 依赖 QEchoIME，并把 QEchoIME.app 嵌入主 App 的 Resources
# 幂等：重复执行不会产生重复 target / 文件引用 / build phase。
#
# 用法：LC_ALL=en_US.UTF-8 ruby scripts/add_ime_target.rb

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../fastv.xcodeproj', __dir__)
SRCROOT = File.dirname(PROJECT_PATH)
IME_TARGET_NAME = 'QEchoIME'
IME_BUNDLE_ID = 'com.17push.inputmethod.QEchoIME'
MARKETING_VERSION = '2.4.0-rc13'
DEPLOYMENT_TARGET = '14.6'
DEVELOPMENT_TEAM = 'ZH2S7D6PL6'
EMBED_PHASE_NAME = 'Embed Input Method'
CONTRACT_PATH = File.join(SRCROOT, 'fastv/Services/InputMethodBridgeContract.swift')

project = Xcodeproj::Project.open(PROJECT_PATH)

main_target = project.targets.find { |t| t.name == 'musetype' }
abort '❌ 找不到 musetype target' unless main_target

# ---------- 1. QEchoIME target ----------

ime_target = project.targets.find { |t| t.name == IME_TARGET_NAME }
if ime_target
  puts "ℹ️  #{IME_TARGET_NAME} target 已存在，跳过创建"
else
  ime_target = project.new_target(:application, IME_TARGET_NAME, :osx, DEPLOYMENT_TARGET)
  puts "✅ 创建 target #{IME_TARGET_NAME}"
end

ime_target.build_configurations.each do |config|
  s = config.build_settings
  s['INFOPLIST_FILE'] = 'QEchoIME/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = IME_BUNDLE_ID
  s['PRODUCT_NAME'] = IME_TARGET_NAME
  s['MARKETING_VERSION'] = MARKETING_VERSION
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['SWIFT_VERSION'] = '5.0'
  s['MACOSX_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = DEVELOPMENT_TEAM
  s['ENABLE_HARDENED_RUNTIME'] = 'YES'
  s['SKIP_INSTALL'] = 'YES'
  s['COMBINE_HIDPI_IMAGES'] = 'YES'
  # librime 集成
  s['SWIFT_OBJC_BRIDGING_HEADER'] = 'QEchoIME/QEchoIME-Bridging-Header.h'
  s['HEADER_SEARCH_PATHS'] = ['$(inherited)', '$(SRCROOT)/ThirdParty/librime/include']
  s['LIBRARY_SEARCH_PATHS'] = ['$(inherited)', '$(SRCROOT)/ThirdParty/librime/lib']
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
end

# ---------- 2. QEchoIME 源文件 ----------

ime_group = project.main_group['QEchoIME'] || project.main_group.new_group('QEchoIME', 'QEchoIME')

def ensure_ref(group, path)
  name = File.basename(path)
  existing = group.files.find { |f| File.basename(f.path.to_s) == name }
  existing || group.new_reference(path)
end

def ensure_source(target, file_ref)
  already = target.source_build_phase.files_references.include?(file_ref)
  target.add_file_references([file_ref]) unless already
end

%w[main.swift QEchoIMEController.swift VoiceCommitServer.swift RimeEngine.swift
   IMESettingsCoordinator.swift CandidateWindow.swift CandidateContentView.swift].each do |name|
  ensure_source(ime_target, ensure_ref(ime_group, File.join(SRCROOT, 'QEchoIME', name)))
end
ensure_ref(ime_group, File.join(SRCROOT, 'QEchoIME', 'Info.plist')) # 只挂引用，不进编译
ensure_ref(ime_group, File.join(SRCROOT, 'QEchoIME', 'QEchoIME-Bridging-Header.h'))

# 共享文件：musetype 经同步 group 自动入编，这里只需补 QEchoIME 侧
ensure_source(ime_target, ensure_ref(ime_group, CONTRACT_PATH))
ensure_source(ime_target, ensure_ref(ime_group, File.join(SRCROOT, 'fastv/Services/RimeKeyMapping.swift')))

# ---------- 2.5 librime：链接 + 嵌入 dylib + RimeData 资源 ----------

dylib_ref = ensure_ref(ime_group, File.join(SRCROOT, 'ThirdParty/librime/lib/librime.1.dylib'))
unless ime_target.frameworks_build_phase.files_references.include?(dylib_ref)
  ime_target.frameworks_build_phase.add_file_reference(dylib_ref)
  puts '✅ QEchoIME 链接 librime.1.dylib'
end

embed_libs = ime_target.copy_files_build_phases.find { |p| p.name == 'Embed Libraries' }
unless embed_libs
  embed_libs = ime_target.new_copy_files_build_phase('Embed Libraries')
  embed_libs.symbol_dst_subfolder_spec = :frameworks
  puts '✅ 创建 QEchoIME Embed Libraries phase'
end
unless embed_libs.files_references.include?(dylib_ref)
  dylib_build_file = embed_libs.add_file_reference(dylib_ref)
  dylib_build_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy] }
  puts '✅ librime.1.dylib 加入嵌入列表'
end

rimedata_ref = ime_group.children.find { |c| c.path.to_s.end_with?('RimeData') }
rimedata_ref ||= ime_group.new_reference(File.join(SRCROOT, 'QEchoIME/RimeData'))
unless ime_target.resources_build_phase.files_references.include?(rimedata_ref)
  ime_target.add_resources([rimedata_ref])
  puts '✅ RimeData 目录加入 bundle 资源'
end

# ---------- 2.6 输入源图标 + 菜单本地化资源 ----------

icon_ref = ensure_ref(ime_group, File.join(SRCROOT, 'QEchoIME/Resources/QEchoIMETemplate.pdf'))
unless ime_target.resources_build_phase.files_references.include?(icon_ref)
  ime_target.add_resources([icon_ref])
  puts '✅ 输入源图标 QEchoIMETemplate.pdf 加入 bundle 资源'
end

%w[zh-Hans en ja ko yue].each do |locale|
  lproj_path = File.join(SRCROOT, "QEchoIME/Resources/#{locale}.lproj")
  lproj_ref = ime_group.children.find { |c| c.path.to_s.end_with?("#{locale}.lproj") }
  lproj_ref ||= ime_group.new_reference(lproj_path)
  unless ime_target.resources_build_phase.files_references.include?(lproj_ref)
    ime_target.add_resources([lproj_ref])
    puts "✅ #{locale}.lproj 加入 bundle 资源"
  end
end

# ---------- 3. 依赖 + 嵌入 ----------

unless main_target.dependencies.any? { |d| d.target == ime_target }
  main_target.add_dependency(ime_target)
  puts '✅ 添加 musetype → QEchoIME 依赖'
end

embed_phase = main_target.copy_files_build_phases.find { |p| p.name == EMBED_PHASE_NAME }
unless embed_phase
  embed_phase = main_target.new_copy_files_build_phase(EMBED_PHASE_NAME)
  embed_phase.symbol_dst_subfolder_spec = :resources
  puts "✅ 创建 copy files phase：#{EMBED_PHASE_NAME}"
end

product_ref = ime_target.product_reference
unless embed_phase.files_references.include?(product_ref)
  build_file = embed_phase.add_file_reference(product_ref)
  build_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
  puts '✅ 把 QEchoIME.app 加入嵌入列表'
end

project.save
puts "✅ 已保存 #{PROJECT_PATH}"
