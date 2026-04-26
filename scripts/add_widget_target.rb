#!/usr/bin/env ruby
# Adds an OffScriptWidgets app extension target to the OffScript Xcode project.
# Idempotent — re-running does nothing if the target already exists.

require 'xcodeproj'
require 'pathname'

PROJECT_PATH = File.expand_path('../OffScript.xcodeproj', __dir__)
WIDGET_NAME = 'OffScriptWidgets'
WIDGET_DIR = File.expand_path("../#{WIDGET_NAME}", __dir__)
APP_TARGET = 'OffScript'
APP_BUNDLE_ID = 'com.offscript.app'
WIDGET_BUNDLE_ID = "#{APP_BUNDLE_ID}.widgets"
DEPLOYMENT = '26.2'

# Files in the main app that the widget also needs to compile.
SHARED_SOURCES = [
  'OffScript/NowPlayingAttributes.swift',
  'OffScript/SharedPlaybackIntents.swift'
]

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == WIDGET_NAME }
  puts "Target '#{WIDGET_NAME}' already exists — nothing to do."
  exit 0
end

app_target = project.targets.find { |t| t.name == APP_TARGET }
abort "Cannot find app target #{APP_TARGET}" unless app_target

# Use the same iOS deployment target as the app, fall back to constant.
ios_deployment = app_target.build_configurations.first
  .build_settings['IPHONEOS_DEPLOYMENT_TARGET'] || DEPLOYMENT

# 1. Create the new target — `:app_extension` produces a .appex bundle.
widget_target = project.new_target(
  :app_extension,
  WIDGET_NAME,
  :ios,
  ios_deployment
)

# 2. Configure build settings on the widget target.
widget_target.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = WIDGET_BUNDLE_ID
  bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
  bs['INFOPLIST_FILE'] = "#{WIDGET_NAME}/Info.plist"
  bs['INFOPLIST_KEY_CFBundleDisplayName'] = 'OffScript Widgets'
  bs['INFOPLIST_KEY_NSHumanReadableCopyright'] = ''
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  bs['CODE_SIGN_IDENTITY'] = '-'
  bs['DEVELOPMENT_TEAM'] = ''
  bs['SWIFT_VERSION'] = '5.0'
  bs['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = ios_deployment
  bs['TARGETED_DEVICE_FAMILY'] = '1,2'
  bs['SKIP_INSTALL'] = 'YES'
  bs['ENABLE_PREVIEWS'] = 'YES'
  bs['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'WIDGET_EXTENSION $(inherited)'
  bs['GENERATE_INFOPLIST_FILE'] = 'NO'
  bs['CURRENT_PROJECT_VERSION'] = '1'
  bs['MARKETING_VERSION'] = '1.0'
end

# 3. Add the widget folder as a synchronized root group so any .swift file
#    dropped into OffScriptWidgets/ shows up in the target automatically —
#    matching the main app's structure.
main_group = project.main_group
sync_group = main_group.new_file(WIDGET_NAME)
sync_group.set_source_tree('SOURCE_ROOT')
sync_group.set_path(WIDGET_NAME)

# Add Swift files in OffScriptWidgets/ to the widget target compile phase.
Dir.glob(File.join(WIDGET_DIR, '*.swift')).sort.each do |path|
  rel = Pathname.new(path).relative_path_from(Pathname.new(File.dirname(PROJECT_PATH))).to_s
  file_ref = project.new_file(rel)
  widget_target.add_file_references([file_ref])
end

# 4. Add the shared files (already part of app target) to widget compile phase.
SHARED_SOURCES.each do |rel|
  abs = File.expand_path(rel, File.dirname(PROJECT_PATH))
  abort "Missing shared source: #{rel}" unless File.exist?(abs)
  ref = project.files.find { |f| f.real_path.to_s == abs }
  if ref.nil?
    ref = project.new_file(rel)
  end
  widget_target.source_build_phase.add_file_reference(ref, true) unless
    widget_target.source_build_phase.files_references.include?(ref)
end

# 5. Embed the widget into the main app so it ships inside OffScript.app.
embed_phase = app_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
unless embed_phase
  embed_phase = app_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
end
build_file = embed_phase.add_file_reference(widget_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# 6. Make the app depend on the widget target.
app_target.add_dependency(widget_target)

project.save
puts "Added #{WIDGET_NAME} extension target with bundle ID #{WIDGET_BUNDLE_ID}"
