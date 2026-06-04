# frozen_string_literal: true

require "ffi"
require "json"

module Sqlglot
  # Low-level FFI bindings to libsqlglot_rust.
  #
  # This module is not intended for direct use -- see the public API on
  # {Sqlglot} instead.  All returned C strings are freed via +sqlglot_free+
  # in +ensure+ blocks so callers never need to manage memory.
  #
  # @api private
  module Native
    extend FFI::Library

    # Locate the shared library.  Search order:
    #   1. SQLGLOT_LIB_PATH environment variable (explicit override)
    #   2. lib/sqlglot/ inside the gem (where extconf.rb copies the build)
    #   3. ext/sqlglot_rust/sql-glot-rust/target/release/ (dev builds)
    #   4. System library path (LD_LIBRARY_PATH / DYLD_LIBRARY_PATH)
    LIB_NAME = "sqlglot_rust"

    SOEXT = FFI::Platform::LIBSUFFIX # "so" on Linux, "dylib" on macOS

    def self.find_library
      # 1. Explicit override
      if (env_path = ENV["SQLGLOT_LIB_PATH"])
        return env_path if File.exist?(env_path)
      end

      gem_root = File.expand_path("../..", __dir__)

      candidates = [
        # 2. Installed location (lib/sqlglot/)
        File.join(gem_root, "lib", "sqlglot", "lib#{LIB_NAME}.#{SOEXT}"),
        # 3. Dev build location
        File.join(gem_root, "ext", "sqlglot_rust", "sql-glot-rust",
                  "target", "release", "lib#{LIB_NAME}.#{SOEXT}"),
      ]

      candidates.each { |path| return path if File.exist?(path) }

      # 4. System path fallback (FFI will search LD_LIBRARY_PATH etc.)
      LIB_NAME
    end

    begin
      ffi_lib find_library
    rescue LoadError => e
      raise Sqlglot::LibraryNotFoundError,
            "Could not load libsqlglot_rust. #{e.message}\n\n" \
            "Make sure the Rust library is built. Run:\n" \
            "  rake cargo:build\n\n" \
            "Or set SQLGLOT_LIB_PATH to the full path of the .so/.dylib file."
    end

    # ── C function declarations ────────────────────────────────────────

    # char *sqlglot_parse(const char *sql, const char *dialect);
    attach_function :sqlglot_parse, [:string, :string], :pointer

    # char *sqlglot_transpile(const char *sql, const char *from, const char *to);
    attach_function :sqlglot_transpile, [:string, :string, :string], :pointer

    # char *sqlglot_generate(const char *ast_json, const char *dialect);
    attach_function :sqlglot_generate, [:string, :string], :pointer

    # const char *sqlglot_version(void);
    attach_function :sqlglot_version, [], :string

    # void sqlglot_free(char *ptr);
    attach_function :sqlglot_free, [:pointer], :void

    # ── Safe wrappers ──────────────────────────────────────────────────

    # Read a C string returned by the FFI, free it, and return a Ruby String.
    # Raises the given error class if the pointer is NULL.
    #
    # @param ptr [FFI::Pointer]
    # @param error_class [Class<Sqlglot::Error>]
    # @param message [String]
    # @return [String]
    def self.read_and_free(ptr, error_class:, message:)
      if ptr.null?
        raise error_class, message
      end

      ptr.read_string.force_encoding("UTF-8")
    ensure
      sqlglot_free(ptr) if ptr && !ptr.null?
    end

    # Parse SQL and return the JSON AST string.
    #
    # @param sql [String]
    # @param dialect [String, nil]
    # @return [String] JSON string
    def self.parse(sql, dialect)
      ptr = sqlglot_parse(sql, dialect)
      read_and_free(ptr,
                    error_class: ParseError,
                    message: "Failed to parse SQL: #{sql.inspect}")
    end

    # Transpile SQL from one dialect to another.
    #
    # @param sql [String]
    # @param from_dialect [String, nil]
    # @param to_dialect [String, nil]
    # @return [String] transpiled SQL
    def self.transpile(sql, from_dialect, to_dialect)
      ptr = sqlglot_transpile(sql, from_dialect, to_dialect)
      read_and_free(ptr,
                    error_class: TranspileError,
                    message: "Failed to transpile SQL: #{sql.inspect}")
    end

    # Generate SQL from a JSON AST string.
    #
    # @param ast_json [String]
    # @param dialect [String, nil]
    # @return [String] generated SQL
    def self.generate(ast_json, dialect)
      ptr = sqlglot_generate(ast_json, dialect)
      read_and_free(ptr,
                    error_class: GenerateError,
                    message: "Failed to generate SQL from AST")
    end

    # Return the library version string.
    #
    # @return [String]
    def self.version
      sqlglot_version()
    end
  end
end
