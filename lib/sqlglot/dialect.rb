# frozen_string_literal: true

module Sqlglot
  # Constants for all 30 SQL dialects supported by sql-glot-rust.
  #
  # Each constant holds the string name passed to the Rust FFI.
  # Use symbols or strings interchangeably in the public API --
  # {Dialect.resolve} normalizes them.
  #
  # @example
  #   Sqlglot.transpile(sql, from: Sqlglot::Dialect::POSTGRES, to: Sqlglot::Dialect::BIGQUERY)
  #   Sqlglot.transpile(sql, from: :postgres, to: :bigquery)  # same thing
  module Dialect
    # ── Official dialects ──────────────────────────────────────
    ANSI       = "ansi"
    ATHENA     = "athena"
    BIGQUERY   = "bigquery"
    CLICKHOUSE = "clickhouse"
    DATABRICKS = "databricks"
    DUCKDB     = "duckdb"
    HIVE       = "hive"
    MYSQL      = "mysql"
    ORACLE     = "oracle"
    POSTGRES   = "postgres"
    PRESTO     = "presto"
    REDSHIFT   = "redshift"
    SNOWFLAKE  = "snowflake"
    SPARK      = "spark"
    SQLITE     = "sqlite"
    STARROCKS  = "starrocks"
    TRINO      = "trino"
    TSQL       = "tsql"

    # ── Community dialects ─────────────────────────────────────
    DORIS       = "doris"
    DREMIO      = "dremio"
    DRILL       = "drill"
    DRUID       = "druid"
    EXASOL      = "exasol"
    FABRIC      = "fabric"
    MATERIALIZE = "materialize"
    PRQL        = "prql"
    RISINGWAVE  = "risingwave"
    SINGLESTORE = "singlestore"
    TABLEAU     = "tableau"
    TERADATA    = "teradata"

    # Common aliases accepted by the Rust library's Dialect::from_str.
    ALIASES = {
      "postgresql" => POSTGRES,
      "mssql"      => TSQL,
      "sqlserver"  => TSQL,
      "mariadb"    => MYSQL,
    }.freeze

    # All known dialect names (constants + aliases).
    ALL = constants
      .reject { |c| %i[ALIASES ALL].include?(c) }
      .map { |c| const_get(c) }
      .freeze

    # Normalize a dialect argument to the string the Rust FFI expects.
    #
    # Accepts symbols, strings, or nil. Unknown values raise ArgumentError.
    #
    # @param name [Symbol, String, nil]
    # @return [String, nil] the dialect string, or nil if name is nil
    def self.resolve(name)
      return nil if name.nil?

      key = name.to_s.downcase.strip
      return key if ALL.include?(key)
      return ALIASES[key] if ALIASES.key?(key)

      raise ArgumentError, "Unknown dialect: #{name.inspect}. " \
                           "Known dialects: #{ALL.sort.join(', ')}"
    end
  end
end
