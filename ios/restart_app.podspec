#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint restart_app.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'restart_app'
  s.version          = '1.7.3'
  s.summary          = 'A Flutter plugin to restart the app using native APIs.'
  s.description      = <<-DESC
A Flutter plugin that helps you to restart the whole Flutter app with a single function call by using native APIs.
                       DESC
  s.homepage         = 'https://github.com/gabrimatic/restart_app'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Soroush Yousefpour' => 'https://gabrimatic.info' }
  s.source           = { :path => '.' }
  s.source_files = 'restart_app/Sources/restart_app/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
