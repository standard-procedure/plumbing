# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "standard/rake"

task default: %i[spec standard]

require "opal"
require "opal/rspec/rake_task"

desc "Compile to Javascript"
task :buildjs do
  `opal -I . --esm --compile lib/plumbing.rb > lib/assets/plumbing.js`
end

desc "Run specs in Javascript"
Opal::RSpec::RakeTask.new(:specjs) do |server, task|
  server.append_path "./lib"
  task.default_path = "./spec"
  task.files = FileList["spec/**/*_spec.rb"]
  task.runner = :node
end
