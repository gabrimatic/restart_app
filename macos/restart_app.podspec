Pod::Spec.new do |s|
  s.name             = 'restart_app'
  s.version          = '1.10.1'
  s.summary          = 'Restart Flutter apps from Dart.'
  s.description      = <<-DESC
Restart a Flutter macOS app by launching a new instance and requesting termination of the existing one.
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
