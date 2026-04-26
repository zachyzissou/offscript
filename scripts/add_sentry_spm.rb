#!/usr/bin/env ruby
# Adds the Sentry-Cocoa SPM package to OffScript.xcodeproj and links the
# Sentry product to the OffScript target. Idempotent — re-runs are no-ops.

require 'xcodeproj'

project_path = File.expand_path('../OffScript.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

PACKAGE_URL = 'https://github.com/getsentry/sentry-cocoa.git'
MIN_VERSION = '8.39.0'
PRODUCT_NAME = 'Sentry'

target = project.targets.find { |t| t.name == 'OffScript' } \
  or abort 'OffScript target not found'

# Add (or find) the package reference at the project level.
existing_ref = project.root_object.package_references
  .find { |r| r.repositoryURL == PACKAGE_URL }

if existing_ref
  puts "Sentry SPM reference already present"
  ref = existing_ref
else
  ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  ref.repositoryURL = PACKAGE_URL
  ref.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => MIN_VERSION }
  project.root_object.package_references << ref
  puts "Added Sentry SPM reference"
end

# Add (or find) the product dependency on the target.
existing_dep = target.package_product_dependencies
  .find { |d| d.product_name == PRODUCT_NAME }

if existing_dep
  puts "Sentry product dependency already linked to OffScript"
else
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = ref
  dep.product_name = PRODUCT_NAME
  target.package_product_dependencies << dep

  # Frameworks build phase needs a build file pointing at the product dep.
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  target.frameworks_build_phase.files << build_file
  puts "Linked Sentry product to OffScript target"
end

project.save
puts "Saved #{project_path}"
