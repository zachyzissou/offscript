#!/usr/bin/env ruby
# Attaches Config/Secrets.xcconfig as the base configuration for both
# Debug and Release of the OffScript target so SENTRY_DSN flows from the
# xcconfig into the build settings (and from there into Info.plist via
# $(SENTRY_DSN) substitution). Idempotent.

require 'xcodeproj'

project_path = File.expand_path('../OffScript.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'OffScript' } \
  or abort 'OffScript target not found'

xcconfig_relative = 'Config/Secrets.xcconfig'

# Find or create a project-level file reference for the xcconfig.
file_ref = project.files.find { |f| f.path == xcconfig_relative }
if file_ref.nil?
  group = project.main_group['Config'] || project.main_group.new_group('Config', 'Config')
  file_ref = group.new_reference(xcconfig_relative)
  file_ref.last_known_file_type = 'text.xcconfig'
  puts "Added Config/Secrets.xcconfig file reference"
end

target.build_configurations.each do |config|
  if config.base_configuration_reference.nil?
    config.base_configuration_reference = file_ref
    puts "Wired #{config.name} base configuration -> Config/Secrets.xcconfig"
  else
    puts "#{config.name} already has a base xcconfig; leaving alone"
  end
end

project.save
puts "Saved #{project_path}"
