#!/usr/bin/env ruby
# Strips/restores the widget extension from the app's archive surface so we can
# upload a TestFlight build before the widget bundle ID + App Group are
# registered in App Store Connect.
#
#   ruby toggle_widget_for_archive.rb strip      # remove widget from app embed/dep
#   ruby toggle_widget_for_archive.rb restore    # re-add it

require 'xcodeproj'

PROJECT_PATH = File.expand_path('../OffScript.xcodeproj', __dir__)
APP = 'OffScript'
WIDGET = 'OffScriptWidgets'
MODE = ARGV[0] or abort "Usage: #{$0} strip|restore"

project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == APP } or abort "missing #{APP}"
widget = project.targets.find { |t| t.name == WIDGET } or abort "missing #{WIDGET}"

embed = app.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }

case MODE
when 'strip'
  if embed
    embed.files.dup.each do |bf|
      embed.remove_build_file(bf) if bf.file_ref&.path&.include?('OffScriptWidgets')
    end
    puts "Removed widget product from Embed App Extensions"
  end
  app.dependencies.dup.each do |dep|
    if dep.target&.name == WIDGET
      app.dependencies.delete(dep)
      puts "Removed dependency on #{WIDGET}"
    end
  end
when 'restore'
  unless app.dependencies.any? { |d| d.target&.name == WIDGET }
    app.add_dependency(widget)
    puts "Re-added dependency on #{WIDGET}"
  end
  embed ||= begin
    p = app.new_copy_files_build_phase('Embed App Extensions')
    p.symbol_dst_subfolder_spec = :plug_ins
    p
  end
  unless embed.files_references.include?(widget.product_reference)
    bf = embed.add_file_reference(widget.product_reference)
    bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
    puts "Re-embedded widget product"
  end
else
  abort "unknown mode #{MODE}"
end

project.save
