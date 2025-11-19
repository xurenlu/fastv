# Uncomment the next line to define a global platform for your project
platform :osx, '11.0'

# CocoaPods analytics sends network stats synchronously affecting flutter build latency.
use_frameworks!

target 'fastv' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for fastv
  pod 'onnxruntime-mobile-objc', '~> 1.15.0'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '11.0' if target.platform_name == :ios
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0' if target.platform_name == :osx
    end
  end
end

