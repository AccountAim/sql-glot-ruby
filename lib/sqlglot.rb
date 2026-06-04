# frozen_string_literal: true

require_relative "sqlglot/version"
require_relative "sqlglot/error"
require_relative "sqlglot/dialect"
require_relative "sqlglot/native"
require_relative "sqlglot/ast_walker"
require_relative "sqlglot/query"

# Load the Railtie only when Rails is present.
require_relative "sqlglot/railtie" if defined?(Rails::Railtie)

# Sqlglot wraps the sql-glot-rust library, providing SQL parsing,
# transpilation across 30+ dialects, and query metadata extraction.
#
# @example Transpile SQL between dialects
#   Sqlglot.transpile("SELECT NOW()", from: :postgres, to: :bigquery)
#   # => "SELECT CURRENT_TIMESTAMP()"
#
# @example Parse SQL into an AST Hash
#   ast = Sqlglot.parse("SELECT a FROM t", dialect: :mysql)
#   # => {"Select" => {"columns" => [...], ...}}
#
# @example Extract query metadata
#   q = Sqlglot::Query.new("SELECT a FROM users AS u JOIN orders AS o ON u.id = o.user_id")
#   q.tables       # => ["users", "orders"]
#   q.columns_dict # => {select: ["a"], join: ["users.id", "orders.user_id"]}
module Sqlglot
  # ── Configuration ────────────────────────────────────────────────────

  class Configuration
    # Default dialect used when no dialect is specified.
    # @return [Symbol, String, nil]
    attr_accessor :default_dialect

    def initialize
      @default_dialect = nil
    end
  end

  class << self
    # @return [Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Yields the configuration object for modification.
    #
    # @example
    #   Sqlglot.configure do |config|
    #     config.default_dialect = :postgres
    #   end
    def configure
      yield(configuration)
    end

    # ── Public API ───────────────────────────────────────────────────

    # Parse a SQL string into a Ruby Hash representing the AST.
    #
    # @param sql [String] the SQL to parse
    # @param dialect [Symbol, String, nil] source dialect (default: configured or ANSI)
    # @return [Hash] the deserialized AST
    # @raise [Sqlglot::ParseError] if parsing fails
    def parse(sql, dialect: nil)
      dialect_str = resolve_dialect(dialect)
      json = Native.parse(sql, dialect_str)
      JSON.parse(json)
    end

    # Transpile SQL from one dialect to another.
    #
    # @param sql [String] the SQL to transpile
    # @param from [Symbol, String, nil] source dialect
    # @param to [Symbol, String, nil] target dialect
    # @return [String] the transpiled SQL
    # @raise [Sqlglot::TranspileError] if transpilation fails
    def transpile(sql, from: nil, to: nil)
      from_str = resolve_dialect(from)
      to_str   = resolve_dialect(to)
      Native.transpile(sql, from_str, to_str)
    end

    # Generate SQL from an AST Hash for a given dialect.
    #
    # @param ast [Hash] an AST previously returned by {.parse}
    # @param dialect [Symbol, String, nil] target dialect
    # @return [String] the generated SQL
    # @raise [Sqlglot::GenerateError] if generation fails
    def generate(ast, dialect: nil)
      dialect_str = resolve_dialect(dialect)
      ast_json = JSON.generate(ast)
      Native.generate(ast_json, dialect_str)
    end

    # Return the version of the underlying sql-glot-rust library.
    #
    # @return [String] e.g. "0.10.0"
    def version
      Native.version
    end

    private

    def resolve_dialect(name)
      name = configuration.default_dialect if name.nil?
      Dialect.resolve(name)
    end
  end
end
