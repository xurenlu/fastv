# Uncomment the next line to define a global platform for your project
platform :osx, '11.0'

# CocoaPods analytics sends network stats synchronously affecting flutter build latency.
use_frameworks!

target 'musetype' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for fastv
  # onnxruntime-mobile-objc 不支持 macOS，已手动集成到项目中
  # pod 'onnxruntime-mobile-objc', '~> 1.15.0'
  # MailCore2 已弃用且网络连接有问题，暂时移除
  # 后续可以手动集成 MailCore2 或使用其他邮件库
  # pod 'MailCore2', '~> 0.6.4'
  pod 'GRDB.swift', :git => 'https://github.com/groue/GRDB.swift.git', :tag => 'v6.25.0'
  # SwiftIdenticon 可能不存在，使用自定义实现
  # pod 'SwiftIdenticon', '~> 2.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '11.0' if target.platform_name == :ios
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0' if target.platform_name == :osx
    end
  end
end
