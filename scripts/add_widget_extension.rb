#!/usr/bin/env ruby
# Adds the OffScriptWidgets extension target to OffScript.xcodeproj.
# Idempotent — re-runs are no-ops.
#
# What this sets up:
#   - New PBXNativeTarget "OffScriptWidgets" (productType app-extension)
#   - PBXFileSystemSynchronizedRootGroup pointing at OffScriptWidgets/
#     (matches how the main OffScript target consumes its sources)
#   - Build settings (bundle ID, entitlements, deployment target, etc.)
#   - Embed Foundation Extensions phase on the host OffScript target
#   - App Group "group.com.offscript.app" wired into both targets via
#     entitlement files that already exist in the repo
#
# After running this:
#   - Re-open Xcode (or run xcodebuild) to pick up the new target
#   - The main OffScript target keeps building exactly as before
#   - The OffScriptWidgets target builds the widget bundle + Live Activity

require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
project_path = File.join(ROOT, 'OffScript.xcodeproj')
project = Xcodeproj::Project.open(project_path)

EXTENSION_NAME    = 'OffScriptWidgets'
EXTENSION_BUNDLE  = 'com.offscript.app.widgets'
EXTENSION_FOLDER  = File.join(ROOT, EXTENSION_NAME)
ENTITLEMENT_FILE  = "#{EXTENSION_NAME}/#{EXTENSION_NAME}.entitlements"
INFO_PLIST_FILE   = "#{EXTENSION_NAME}/Info.plist"
DEPLOYMENT_TARGET = '17.0'

# Bail if the extension target already exists. Idempotent.
existing_target = project.targets.find { |t| t.name == EXTENSION_NAME }
host_target = project.targets.find { |t| t.name == 'OffScript' } \
  or abort 'OffScript host target not found'

if existing_target
  puts "Extension target #{EXTENSION_NAME} already exists — nothing to do."
else
  # 1. Create the synchronized root group so Xcode mirrors files in the folder.
  sync_group = Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup.new(
    project,
    project.generate_uuid
  )
  sync_group.path = EXTENSION_NAME
  sync_group.source_tree = '<group>'
  sync_group.explicit_file_types = {}
  sync_group.explicit_folders = []
  project.objects_by_uuid[sync_group.uuid] = sync_group
  project.main_group.children << sync_group

  # 2. Create the new native target.
  target = project.new(Xcodeproj::Project::Object::PBXNativeTarget)
  target.name = EXTENSION_NAME
  target.product_name = EXTENSION_NAME
  target.product_type = 'com.apple.product-type.app-extension'
  target.build_configuration_list = Xcodeproj::Project::ProjectHelper
    .configuration_list(project, :ios, DEPLOYMENT_TARGET, target, :swift)
  project.targets << target

  # Wire the synchronized group as the target's source root.
  target.file_system_synchronized_groups ||= []
  target.file_system_synchronized_groups << sync_group

  # 3. Per-config build settings.
  target.build_configurations.each do |config|
    config.build_settings.merge!(
      'PRODUCT_BUNDLE_IDENTIFIER'         => EXTENSION_BUNDLE,
      'PRODUCT_NAME'                      => '$(TARGET_NAME)',
      'INFOPLIST_FILE'                    => INFO_PLIST_FILE,
      'CODE_SIGN_ENTITLEMENTS'            => ENTITLEMENT_FILE,
      'IPHONEOS_DEPLOYMENT_TARGET'        => DEPLOYMENT_TARGET,
      'TARGETED_DEVICE_FAMILY'            => '1,2',
      'SKIP_INSTALL'                      => 'YES',
      'SWIFT_VERSION'                     => '5.0',
      'GENERATE_INFOPLIST_FILE'           => 'NO',
      'CODE_SIGN_STYLE'                   => 'Automatic',
      'DEVELOPMENT_TEAM'                  => 'TNRU46733N',
      'ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOLS' => 'NO',
      'LD_RUNPATH_SEARCH_PATHS'           => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks',
      'MARKETING_VERSION'                 => '1.0',
      'CURRENT_PROJECT_VERSION'           => '1',
      'INFOPLIST_KEY_NSHumanReadableCopyright' => '',
      'SWIFT_EMIT_LOC_STRINGS'            => 'YES'
    )
  end

  # 4. Embed the extension into the host app via "Embed Foundation Extensions".
  embed_phase = host_target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :plug_ins } \
    || host_target.new_copy_files_build_phase('Embed Foundation Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
  embed_phase.name = 'Embed Foundation Extensions'

  product_ref = target.product_reference
  unless embed_phase.files_references.include?(product_ref)
    build_file = embed_phase.add_file_reference(product_ref)
    build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  end

  # 5. Add target dependency from host app to extension.
  unless host_target.dependencies.any? { |d| d.target == target }
    host_target.add_dependency(target)
  end

  # 6. Make sure the host app's entitlements wire the App Group too.
  host_target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_ENTITLEMENTS'] ||= 'OffScript/OffScript.entitlements'
  end

  puts "Created #{EXTENSION_NAME} extension target."
end

project.save
puts "Saved #{project_path}"
