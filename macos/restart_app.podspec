Pod::Spec.new do |s|
  s.name             = 'restart_app'
  s.version          = '1.8.1'
  s.summary          = 'A Flutter plugin to restart or relaunch apps with platform-specific behavior.'
  s.description      = <<-DESC
A Flutter plugin that helps restart or relaunch Flutter apps with platform-specific behavior.
                       DESC
  s.homepage         = 'https://github.com/gabrimatic/restart_app'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Soroush Yousefpour' => 'https://gabrimatic.info' }
  s.source           = { :path => '.' }
  s.source_files = 'restart_app/Sources/restart_app/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
