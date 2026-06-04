# frozen_string_literal: true

module Sqlglot
  # Base error for all Sqlglot errors.
  class Error < StandardError; end

  # Raised when the shared library cannot be found or loaded.
  class LibraryNotFoundError < Error; end

  # Raised when SQL parsing fails (the Rust FFI returned NULL).
  class ParseError < Error; end

  # Raised when SQL transpilation fails.
  class TranspileError < Error; end

  # Raised when SQL generation from an AST fails.
  class GenerateError < Error; end
end
