# frozen_string_literal: true

require_relative "lib/sqlglot/version"

Gem::Specification.new do |spec|
  spec.name = "sqlglot"
  spec.version = Sqlglot::VERSION
  spec.authors = ["Accountaim"]
  spec.summary = "Ruby wrapper for sql-glot-rust: a SQL parser, optimizer, and transpiler"
  spec.description = <<~DESC
    A Ruby gem that wraps the sql-glot-rust library via FFI, providing SQL parsing,
    transpilation between 30+ dialects, and query metadata extraction (tables, columns,
    aliases, subqueries, CTEs, etc.) for use in Rails applications.
  DESC
  spec.homepage = "https://github.com/AccountAim/sql-glot-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,ext}/**/*", "Gemfile", "Rakefile", "sqlglot.gemspec"]
  end

  spec.require_paths = ["lib"]
  spec.extensions = ["ext/sqlglot_rust/extconf.rb"]

  spec.add_dependency "ffi", "~> 1.15"

  spec.metadata = {
    "source_code_uri" => "https://github.com/AccountAim/sql-glot-ruby",
    "rubygems_mfa_required" => "true"
  }
end
