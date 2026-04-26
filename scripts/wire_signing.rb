#!/usr/bin/env ruby
# Wires automatic signing with the user's Apple Developer Team ID.
# Idempotent — safe to re-run.

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../OffScript.xcodeproj', __dir__)
TEAM_ID = ARGV[0] or abort "Usage: ruby wire_signing.rb <TEAM_ID> [build_number]"
NEW_BUILD = ARGV[1] # optional — bumps CURRENT_PROJECT_VERSION

project = Xcodeproj::Project.open(PROJECT_PATH)

%w[OffScript OffScriptWidgets].each do |target_name|
  target = project.targets.find { |t| t.name == target_name }
  abort "missing target #{target_name}" unless target

  target.build_configurations.each do |config|
    bs = config.build_settings
    bs['DEVELOPMENT_TEAM'] = TEAM_ID
    bs['CODE_SIGN_STYLE'] = 'Automatic'
    bs.delete('PROVISIONING_PROFILE_SPECIFIER')
    bs.delete('PROVISIONING_PROFILE')
    if config.name == 'Release'
      bs['CODE_SIGN_IDENTITY'] = 'Apple Development'
    end
    if NEW_BUILD
      bs['CURRENT_PROJECT_VERSION'] = NEW_BUILD
    end
  end
end

# Project-level attributes — set the dev team there too so Xcode UI shows it.
project.root_object.attributes['TargetAttributes'] ||= {}
%w[OffScript OffScriptWidgets].each do |target_name|
  target = project.targets.find { |t| t.name == target_name }
  attrs = project.root_object.attributes['TargetAttributes'][target.uuid] ||= {}
  attrs['DevelopmentTeam'] = TEAM_ID
  attrs['ProvisioningStyle'] = 'Automatic'
end

project.save
puts "Wired DEVELOPMENT_TEAM = #{TEAM_ID} on app + widget targets"
puts "Build number: #{NEW_BUILD}" if NEW_BUILD
