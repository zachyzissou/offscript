#!/usr/bin/env ruby
# Inverse of add_widget_extension.rb — strips the OffScriptWidgets target
# from OffScript.xcodeproj so CI can build + sign the host app without
# needing the widget bundle ID registered in App Store Connect first.
#
# Why this exists: the widget extension introduced two new failure modes
# that block CI signing until they're fixed manually in the Apple Developer
# portal:
#   1. New bundle ID `com.offscript.app.widgets` needs an App ID with the
#      App Groups capability registered.
#   2. App Group `group.com.offscript.app` needs to exist in the developer
#      account and be wired into both bundle IDs' provisioning profiles.
#
# Once those are set up, run `scripts/add_widget_extension.rb` to put the
# target back. The Swift sources in OffScriptWidgets/ stay in the repo
# either way — this script only mutates the project file.

require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
project_path = File.join(ROOT, 'OffScript.xcodeproj')
project = Xcodeproj::Project.open(project_path)

EXTENSION_NAME = 'OffScriptWidgets'

target = project.targets.find { |t| t.name == EXTENSION_NAME }
unless target
  puts "#{EXTENSION_NAME} target not found — nothing to do."
  exit 0
end

host_target = project.targets.find { |t| t.name == 'OffScript' }

if host_target
  # Remove the embed-extensions phase entry pointing at the widget product.
  host_target.copy_files_build_phases.each do |phase|
    next unless phase.symbol_dst_subfolder_spec == :plug_ins

    phase.files.dup.each do |build_file|
      ref = build_file.file_ref || build_file.product_ref
      next unless ref == target.product_reference
      phase.remove_build_file(build_file)
      puts "Removed #{EXTENSION_NAME} from embed phase"
    end
  end

  # Remove the target dependency.
  host_target.dependencies.dup.each do |dep|
    next unless dep.target == target
    host_target.dependencies.delete(dep)
    project.objects_by_uuid.delete(dep.uuid)
    puts "Removed target dependency on #{EXTENSION_NAME}"
  end
end

# Remove the synchronized root group that pointed at OffScriptWidgets/.
sync_groups = project.main_group.children.select do |child|
  child.is_a?(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup) \
    && child.path == EXTENSION_NAME
end
sync_groups.each do |g|
  project.main_group.children.delete(g)
  project.objects_by_uuid.delete(g.uuid)
  puts "Removed synchronized group for #{EXTENSION_NAME}"
end

# Remove the target itself + its product reference.
if (product = target.product_reference)
  product.remove_from_project
end
target.remove_from_project
puts "Removed target #{EXTENSION_NAME}"

project.save
puts "Saved #{project_path}"
