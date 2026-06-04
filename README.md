# Sqlglot

A Ruby gem that wraps [sql-glot-rust](https://github.com/protegrity/sql-glot-rust) via FFI, providing:

- **Parse** SQL into a structured AST (Ruby Hash)
- **Transpile** SQL between 30 dialects (Postgres, MySQL, BigQuery, Snowflake, T-SQL, ...)
- **Generate** SQL from an AST
- **Extract metadata** from queries -- tables, columns, aliases, subqueries, CTEs, values, and more (inspired by Python's [sql-metadata](https://github.com/macbre/sql-metadata))

## Requirements

- Ruby >= 3.0
- Rust toolchain (cargo 1.85+) -- only needed when building from source
- git -- only needed when building from source

## Installation

### Precompiled native gems (recommended)

Precompiled gems are available for these platforms:

- `x86_64-linux-gnu`
- `aarch64-linux-gnu`
- `x86_64-linux-musl`
- `aarch64-linux-musl`
- `x86_64-darwin`
- `arm64-darwin`

No Rust toolchain or compilation is required. Add the GitHub Packages source
to your Gemfile:

```ruby
source "https://rubygems.pkg.github.com/accountaim" do
  gem "sqlglot"
end
```

Bundler must be authenticated with GitHub Packages:

```sh
bundle config https://rubygems.pkg.github.com/accountaim USERNAME:TOKEN
```

Where `TOKEN` is a GitHub personal access token with `read:packages` scope.

### Building from source

On unsupported platforms, the Rust library is compiled automatically during
`gem install` via `extconf.rb`. This requires the Rust toolchain (cargo 1.85+)
and git.

The `github:` and `path:` Gemfile options always build from source, since
Bundler bypasses RubyGems platform selection for these sources:

```ruby
gem "sqlglot", github: "AccountAim/sql-glot-ruby"  # requires Rust
gem "sqlglot", path: "/path/to/this/repo"    # requires Rust
```

For local development, you can also build manually:

```sh
bundle install
rake cargo:build
```

`rake cargo:build` clones [sql-glot-rust](https://github.com/protegrity/sql-glot-rust) at a pinned tag, runs `cargo build --release`, and copies the resulting `.so`/`.dylib` into `lib/sqlglot/`. This only needs to be done once (or when upgrading the Rust library version).

If the `.so` already exists, `extconf.rb` skips the Rust build automatically.

## Usage

### Transpile between dialects

```ruby
Sqlglot.transpile("SELECT NOW()", from: :postgres, to: :bigquery)
# => "SELECT CURRENT_TIMESTAMP()"

Sqlglot.transpile("SELECT * FROM t LIMIT 10", from: :mysql, to: :tsql)
# => "SELECT TOP 10 * FROM t"

Sqlglot.transpile("SELECT NVL(a, b) FROM t", from: :oracle, to: :tsql)
# => "SELECT ISNULL(a, b) FROM t"
```

Dialect arguments accept symbols, strings, or `Sqlglot::Dialect` constants:

```ruby
Sqlglot.transpile(sql, from: :postgres, to: :bigquery)
Sqlglot.transpile(sql, from: "postgres", to: "bigquery")
Sqlglot.transpile(sql, from: Sqlglot::Dialect::POSTGRES, to: Sqlglot::Dialect::BIGQUERY)
```

### Parse SQL to an AST

```ruby
ast = Sqlglot.parse("SELECT name, age FROM users WHERE active = true", dialect: :postgres)
# => {"Select" => {"columns" => [...], "from" => {...}, "where_clause" => {...}, ...}}
```

The return value is a plain Ruby Hash deserialized from the Rust library's JSON AST.

### Generate SQL from an AST

```ruby
ast = Sqlglot.parse("SELECT name FROM users WHERE id = 1")

# Roundtrip back to SQL
Sqlglot.generate(ast)
# => "SELECT name FROM users WHERE id = 1"

# Generate for a different dialect
Sqlglot.generate(ast, dialect: :tsql)
```

### Modify an AST and regenerate

```ruby
ast = Sqlglot.parse("SELECT name FROM users WHERE id = 1")

# Change the WHERE value
ast["Select"]["where_clause"]["BinaryOp"]["right"] = { "Number" => "42" }

Sqlglot.generate(ast)
# => "SELECT name FROM users WHERE id = 42"
```

### Library version

```ruby
Sqlglot.version
# => "0.10.0"
```

## Query Metadata Extraction

`Sqlglot::Query` parses SQL once, then provides lazy-evaluated properties for extracting tables, columns, aliases, and more.

```ruby
q = Sqlglot::Query.new(<<~SQL, dialect: :postgres)
  SELECT u.name, COUNT(o.id) AS order_count
  FROM users AS u
  JOIN orders AS o ON u.id = o.user_id
  WHERE u.active = true
  ORDER BY order_count DESC
  LIMIT 10 OFFSET 20
SQL
```

### Query type

```ruby
q.query_type  # => :select
# Also: :insert, :update, :delete, :create_table, :merge, etc.
```

### Tables

```ruby
q.tables          # => ["users", "orders"]
q.tables_aliases  # => {"u" => "users", "o" => "orders"}
```

CTE names are automatically excluded from the tables list:

```ruby
q = Sqlglot::Query.new("WITH cte AS (SELECT id FROM real_table) SELECT * FROM cte")
q.tables  # => ["real_table"]
```

### Columns

```ruby
q.columns
# => ["users.name", "orders.id", "users.id", "orders.user_id", "users.active"]

# Table aliases are resolved: u.name becomes users.name
```

### Columns by clause

```ruby
q.columns_dict
# => {
#   select:   ["users.name", "orders.id"],
#   join:     ["users.id", "orders.user_id"],
#   where:    ["users.active"],
#   order_by: ["orders.id"]   # resolved from the "order_count" alias
# }
```

### Output columns

What the SELECT would produce (uses aliases where present):

```ruby
q.output_columns  # => ["name", "order_count"]
```

### Column aliases

```ruby
q = Sqlglot::Query.new("SELECT a, b + c AS total FROM t ORDER BY total")

q.columns_aliases        # => {"total" => ["b", "c"]}
q.columns_aliases_names  # => ["total"]
q.columns_aliases_dict   # => {select: ["total"], order_by: ["total"]}
```

### CTEs

```ruby
q = Sqlglot::Query.new(<<~SQL)
  WITH active AS (SELECT * FROM users WHERE active = true)
  SELECT * FROM active
SQL

q.with_names    # => ["active"]
q.with_queries  # => {"active" => "SELECT * FROM users WHERE active = true"}
```

### Subqueries

```ruby
q = Sqlglot::Query.new(<<~SQL)
  SELECT * FROM (SELECT id FROM users) AS sub
  JOIN orders ON sub.id = orders.user_id
SQL

q.subqueries       # => {"sub" => "SELECT id FROM users"}
q.subqueries_names # => ["sub"]
```

### LIMIT and OFFSET

```ruby
q.limit_and_offset  # => [10, 20]

# Returns nil when no LIMIT is present
Sqlglot::Query.new("SELECT 1").limit_and_offset  # => nil
```

### INSERT values

```ruby
q = Sqlglot::Query.new("INSERT INTO users (name, age) VALUES ('Alice', 30)")

q.values       # => ["Alice", 30]
q.values_dict  # => {"name" => "Alice", "age" => 30}

# Auto-generates column names when not specified
q = Sqlglot::Query.new("INSERT INTO t VALUES (1, 'hello')")
q.values_dict  # => {"column_1" => 1, "column_2" => "hello"}
```

### Query generalization

Replaces literals with placeholders for query fingerprinting:

```ruby
q = Sqlglot::Query.new("SELECT * FROM t WHERE id = 42 AND name = 'Alice'")
q.generalize
# => "SELECT * FROM t WHERE id = N AND name = 'X'"
```

### Raw AST access

```ruby
q.ast  # => the full parsed Hash (same as Sqlglot.parse)
```

## Rails Integration

The gem includes a Railtie that loads automatically when Rails is present.

```ruby
# config/application.rb (or an initializer)
config.sqlglot.default_dialect = :sqlite
```

Then dialect can be omitted from calls:

```ruby
Sqlglot.parse("SELECT 1")             # uses :sqlite
Sqlglot.transpile(sql, to: :bigquery) # from: defaults to :sqlite
```

Without Rails, use the configure block:

```ruby
Sqlglot.configure do |c|
  c.default_dialect = :sqlite
end
```

## Supported Dialects

### Official

| Dialect | Constant |
|---|---|
| ANSI SQL | `Sqlglot::Dialect::ANSI` |
| Athena | `Sqlglot::Dialect::ATHENA` |
| BigQuery | `Sqlglot::Dialect::BIGQUERY` |
| ClickHouse | `Sqlglot::Dialect::CLICKHOUSE` |
| Databricks | `Sqlglot::Dialect::DATABRICKS` |
| DuckDB | `Sqlglot::Dialect::DUCKDB` |
| Hive | `Sqlglot::Dialect::HIVE` |
| MySQL | `Sqlglot::Dialect::MYSQL` |
| Oracle | `Sqlglot::Dialect::ORACLE` |
| PostgreSQL | `Sqlglot::Dialect::POSTGRES` |
| Presto | `Sqlglot::Dialect::PRESTO` |
| Redshift | `Sqlglot::Dialect::REDSHIFT` |
| Snowflake | `Sqlglot::Dialect::SNOWFLAKE` |
| Spark | `Sqlglot::Dialect::SPARK` |
| SQLite | `Sqlglot::Dialect::SQLITE` |
| StarRocks | `Sqlglot::Dialect::STARROCKS` |
| Trino | `Sqlglot::Dialect::TRINO` |
| T-SQL | `Sqlglot::Dialect::TSQL` |

### Community

| Dialect | Constant |
|---|---|
| Doris | `Sqlglot::Dialect::DORIS` |
| Dremio | `Sqlglot::Dialect::DREMIO` |
| Drill | `Sqlglot::Dialect::DRILL` |
| Druid | `Sqlglot::Dialect::DRUID` |
| Exasol | `Sqlglot::Dialect::EXASOL` |
| Fabric | `Sqlglot::Dialect::FABRIC` |
| Materialize | `Sqlglot::Dialect::MATERIALIZE` |
| PRQL | `Sqlglot::Dialect::PRQL` |
| RisingWave | `Sqlglot::Dialect::RISINGWAVE` |
| SingleStore | `Sqlglot::Dialect::SINGLESTORE` |
| Tableau | `Sqlglot::Dialect::TABLEAU` |
| Teradata | `Sqlglot::Dialect::TERADATA` |

Aliases are also accepted: `:postgresql`, `:mssql`, `:sqlserver`, `:mariadb`.

## Configuration

| Setting | Description |
|---|---|
| `Sqlglot.configure { \|c\| c.default_dialect = :sqlite }` | Default dialect when none is specified |
| `ENV["SQLGLOT_LIB_PATH"]` | Override the path to `libsqlglot_rust.so` / `.dylib` |

## Development

```sh
git clone <this-repo>
cd sqlglot
bundle install
rake cargo:build    # build the Rust shared library
bundle exec rspec   # run tests (49 examples)
```

## License

MIT
