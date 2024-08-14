# frozen_string_literal: true

require_relative "lib/plumbing/version"

Gem::Specification.new do |spec|
  spec.name = "standard-procedure-plumbing"
  spec.version = Plumbing::VERSION
  spec.authors = ["Rahoul Baruah"]
  spec.email = ["rahoulb@echodek.co"]

  spec.summary = "Plumbing - various pipelines for your ruby application"
  spec.description = "A composable event pipeline and sequential pipelines of operations"
  spec.homepage = "https://github.com/standard-procedure/plumbing"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/standard-procedure/plumbing"
  spec.metadata["changelog_uri"] = "https://github.com/standard-procedure/plumbing/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
