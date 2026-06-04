# frozen_string_literal: true

# Build a platform-specific gem that includes a precompiled native library.
#
# Usage:
#   ruby scripts/build_native_gem.rb PLATFORM
#
# Example:
#   ruby scripts/build_native_gem.rb arm64-darwin
#
# The precompiled library (libsqlglot_rust.so, .dylib, or .dll) must already
# be present in lib/sqlglot/ before running this script.
#
# The resulting .gem file is written to pkg/.

require "rubygems"
require "rubygems/package"
require "fileutils"

platform = ARGV[0]
abort "Usage: #{$0} PLATFORM\n\nExample: #{$0} arm64-darwin" unless platform

gemspec_path = File.expand_path("../sqlglot.gemspec", __dir__)
abort "ERROR: gemspec not found at #{gemspec_path}" unless File.exist?(gemspec_path)

# Verify the precompiled library is present
lib_dir = File.expand_path("../lib/sqlglot", __dir__)
native_libs = Dir[File.join(lib_dir, "libsqlglot_rust.{so,dylib,dll}")]

if native_libs.empty?
  abort "ERROR: No precompiled library found in #{lib_dir}.\n" \
        "Expected libsqlglot_rust.so, .dylib, or .dll"
end

# Load the source gemspec and modify it for a native platform gem
spec = Gem::Specification.load(gemspec_path)

# Set the target platform (e.g., "x86_64-linux-gnu", "arm64-darwin")
spec.platform = Gem::Platform.new(platform)

# Remove the extension so extconf.rb is not invoked on install --
# the precompiled library is already included.
spec.extensions = []

# Include the precompiled library in the gem's file list
native_libs.each do |lib_path|
  relative = lib_path.sub("#{spec.full_gem_path}/", "")
             .sub(%r{^.*/lib/}, "lib/")
  spec.files << relative unless spec.files.include?(relative)
end

# Build the gem
FileUtils.mkdir_p("pkg")
gem_file = Gem::Package.build(spec)
FileUtils.mv(gem_file, "pkg/")

puts "Built pkg/#{File.basename(gem_file)}"
