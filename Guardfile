ignore(/bin/, /checksums/, /pkg/, /sig/, /tmp/)

guard :bundler do
  require "guard/bundler"
  require "guard/bundler/verify"
  helper = Guard::Bundler::Verify.new

  files = ["Gemfile"]
  files += Dir["*.gemspec"] if files.any? { |f| helper.uses_gemspec?(f) }

  files.each { |file| watch(helper.real_path(file)) }
end

guard :rspec, cmd: "bundle exec rspec" do
  require "guard/rspec/dsl"
  dsl = Guard::RSpec::Dsl.new(self)
  rspec = dsl.rspec
  watch(rspec.spec_helper) { rspec.spec_dir }
  watch(rspec.spec_support) { rspec.spec_dir }
  watch(rspec.spec_files)
  ruby = dsl.ruby
  dsl.watch_spec_files_for(ruby.lib_files)
end

guard :standardrb, fix: true, all_on_start: true, progress: true do
  watch(/.+\.rb$/)
end
