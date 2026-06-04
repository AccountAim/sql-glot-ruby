# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

namespace :cargo do
  desc "Build the sql-glot-rust shared library"
  task :build do
    ext_dir = File.expand_path("ext/sqlglot_rust", __dir__)
    rust_dir = File.join(ext_dir, "sql-glot-rust")

    unless Dir.exist?(rust_dir)
      sh "git clone --depth 1 --branch v0.10.0 " \
         "https://github.com/protegrity/sql-glot-rust.git #{rust_dir}"
    end

    sh "cargo build --release --manifest-path #{File.join(rust_dir, 'Cargo.toml')}"

    lib_dir = File.expand_path("lib/sqlglot", __dir__)
    release_dir = File.join(rust_dir, "target", "release")

    so_file = Dir[File.join(release_dir, "libsqlglot_rust.{so,dylib,dll}")].first
    if so_file
      cp so_file, lib_dir, verbose: true
    else
      abort "ERROR: shared library not found in #{release_dir}"
    end
  end
end

task default: :spec
