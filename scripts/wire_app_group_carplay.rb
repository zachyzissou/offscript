#!/usr/bin/env ruby
# Wires App Group entitlements to the OffScript + OffScriptWidgets targets
# and adds SharedNowPlayingState.swift to the widget target's compile phase.
# Idempotent.

require 'xcodeproj'
require 'pathname'

PROJECT_PATH = File.expand_path('../OffScript.xcodeproj', __dir__)
ROOT = File.dirname(PROJECT_PATH)

APP_TARGET = 'OffScript'
APP_ENTITLEMENTS = 'OffScript/OffScript.entitlements'

WIDGET_TARGET = 'OffScriptWidgets'
WIDGET_ENTITLEMENTS = 'OffScriptWidgets/OffScriptWidgets.entitlements'

# Files in the app folder that the widget extension also needs to compile.
ADDITIONAL_SHARED = ['OffScript/SharedNowPlayingState.swift']

project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == APP_TARGET } or abort "no #{APP_TARGET}"
widget = project.targets.find { |t| t.name == WIDGET_TARGET } or abort "no #{WIDGET_TARGET}"

# 1. Set CODE_SIGN_ENTITLEMENTS for both targets.
app.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = APP_ENTITLEMENTS
end
widget.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = WIDGET_ENTITLEMENTS
end

# 2. Make sure the widget compiles each shared file from the app target.
ADDITIONAL_SHARED.each do |rel|
  abs = File.join(ROOT, rel)
  abort "missing #{rel}" unless File.exist?(abs)

  ref = project.files.find { |f| f.real_path.to_s == abs }
  ref ||= project.new_file(rel)

  already = widget.source_build_phase.files_references.include?(ref)
  widget.source_build_phase.add_file_reference(ref, true) unless already
end

project.save
puts "Wired entitlements + shared sources for App Group group.com.offscript.app"
