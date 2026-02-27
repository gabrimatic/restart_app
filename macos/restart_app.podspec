Pod::Spec.new do |s|
  s.name             = 'restart_app'
  s.version          = '1.6.0'
  s.summary          = 'A Flutter plugin to restart the app using native APIs.'
  s.description      = <<-DESC
A Flutter plugin that helps you to restart the whole Flutter app with a single function call by using native APIs.
                       DESC
  s.homepage         = 'https://github.com/gabrimatic/restart_app'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Soroush Yousefpour' => 'https://gabrimatic.info' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
