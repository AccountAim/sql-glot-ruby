# frozen_string_literal: true

# extconf.rb — invoked by `gem install` or `bundle install` to build the
# sql-glot-rust shared library from source.
#
# Requirements:
#   - git (to clone the repository)
#   - cargo / rustc (Rust toolchain, 1.85+)

require "fileutils"

RUST_REPO  = "https://github.com/protegrity/sql-glot-rust.git"
RUST_TAG   = "v0.10.0"
EXT_DIR    = __dir__
RUST_DIR   = File.join(EXT_DIR, "sql-glot-rust")
LIB_DIR    = File.expand_path("../../lib/sqlglot", EXT_DIR)

# ── Skip build if the shared library already exists ────────────────────

so_already_built = Dir[File.join(LIB_DIR, "libsqlglot_rust.{so,dylib,dll}")].any?

if so_already_built
  puts "libsqlglot_rust already exists in #{LIB_DIR}, skipping Rust build."
  File.write(File.join(EXT_DIR, "Makefile"), "all:\ninstall:\nclean:\n")
  exit 0
end

# ── Pre-flight checks ─────────────────────────────────────────────────

def command_exists?(cmd)
  system("command -v #{cmd} > /dev/null 2>&1")
end

unless command_exists?("cargo")
  abort <<~MSG
    ERROR: `cargo` not found on PATH.

    The sqlglot gem requires the Rust toolchain to compile the native library.
    Install Rust via https://rustup.rs and ensure `cargo` is on your PATH,
    then run `gem install sqlglot` again.
  MSG
end

unless command_exists?("git")
  abort "ERROR: `git` not found on PATH. It is needed to fetch the Rust source."
end

# ── Clone the Rust source ─────────────────────────────────────────────

unless Dir.exist?(RUST_DIR)
  puts "Cloning #{RUST_REPO} at #{RUST_TAG}..."
  ok = system("git", "clone", "--depth", "1", "--branch", RUST_TAG, RUST_REPO, RUST_DIR)
  abort "ERROR: git clone failed" unless ok
end

# ── Build the shared library ──────────────────────────────────────────

puts "Building sql-glot-rust (release)..."
ok = system("cargo", "build", "--release",
            "--manifest-path", File.join(RUST_DIR, "Cargo.toml"))
abort "ERROR: cargo build failed" unless ok

# ── Copy the artifact into lib/sqlglot/ ───────────────────────────────

release_dir = File.join(RUST_DIR, "target", "release")

so_glob = File.join(release_dir, "libsqlglot_rust.{so,dylib,dll}")
so_file = Dir[so_glob].first

if so_file
  FileUtils.mkdir_p(LIB_DIR)
  FileUtils.cp(so_file, LIB_DIR, verbose: true)
  puts "Installed #{File.basename(so_file)} into #{LIB_DIR}"
else
  abort "ERROR: shared library not found in #{release_dir}. " \
        "Expected libsqlglot_rust.so, .dylib, or .dll"
end

# ── Write a dummy Makefile (required by rubygems extension protocol) ──

File.write(File.join(EXT_DIR, "Makefile"), <<~MAKEFILE)
  all:
  install:
  clean:
MAKEFILE
