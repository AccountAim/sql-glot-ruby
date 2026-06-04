# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sqlglot::Query do
  # ── query_type ─────────────────────────────────────────────────────

  describe "#query_type" do
    it "detects SELECT" do
      q = described_class.new("SELECT a FROM t")
      expect(q.query_type).to eq(:select)
    end

    it "detects INSERT" do
      q = described_class.new("INSERT INTO t (a) VALUES (1)")
      expect(q.query_type).to eq(:insert)
    end

    it "detects UPDATE" do
      q = described_class.new("UPDATE t SET a = 1 WHERE b = 2")
      expect(q.query_type).to eq(:update)
    end

    it "detects DELETE" do
      q = described_class.new("DELETE FROM t WHERE a = 1")
      expect(q.query_type).to eq(:delete)
    end

    it "detects CREATE TABLE" do
      q = described_class.new("CREATE TABLE t (id INT, name TEXT)")
      expect(q.query_type).to eq(:create_table)
    end
  end

  # ── tables ─────────────────────────────────────────────────────────

  describe "#tables" do
    it "extracts a single table" do
      q = described_class.new("SELECT a FROM users")
      expect(q.tables).to eq(["users"])
    end

    it "extracts multiple tables from JOIN" do
      q = described_class.new(
        "SELECT a.name, b.age FROM users AS a JOIN profiles AS b ON a.id = b.user_id"
      )
      expect(q.tables).to contain_exactly("users", "profiles")
    end

    it "extracts tables from comma-separated FROM" do
      q = described_class.new("SELECT a, b FROM foo, bar")
      expect(q.tables).to contain_exactly("foo", "bar")
    end

    it "excludes CTE names from tables" do
      q = described_class.new(
        "WITH cte AS (SELECT 1 FROM real_table) SELECT * FROM cte"
      )
      expect(q.tables).to eq(["real_table"])
      expect(q.tables).not_to include("cte")
    end
  end

  # ── tables_aliases ─────────────────────────────────────────────────

  describe "#tables_aliases" do
    it "maps alias to real table name" do
      q = described_class.new(
        "SELECT a.name FROM users AS a JOIN orders AS b ON a.id = b.user_id"
      )
      expect(q.tables_aliases).to include("a" => "users", "b" => "orders")
    end

    it "returns empty hash when no aliases" do
      q = described_class.new("SELECT name FROM users")
      expect(q.tables_aliases).to eq({})
    end
  end

  # ── columns ────────────────────────────────────────────────────────

  describe "#columns" do
    it "extracts columns from a simple SELECT" do
      q = described_class.new("SELECT name, age FROM users")
      expect(q.columns).to include("name", "age")
    end

    it "resolves table aliases to real table names" do
      q = described_class.new(
        "SELECT a.name FROM users AS a"
      )
      expect(q.columns).to include("users.name")
    end

    it "includes columns from WHERE clause" do
      q = described_class.new("SELECT name FROM users WHERE active = true")
      expect(q.columns).to include("active")
    end

    it "includes columns from JOIN conditions" do
      q = described_class.new(
        "SELECT a.name FROM users AS a JOIN orders AS o ON a.id = o.user_id"
      )
      expect(q.columns).to include("users.id", "orders.user_id")
    end
  end

  # ── columns_dict ───────────────────────────────────────────────────

  describe "#columns_dict" do
    it "groups columns by clause" do
      q = described_class.new(
        "SELECT u.name FROM users AS u " \
        "JOIN orders AS o ON u.id = o.user_id " \
        "WHERE u.active = true " \
        "ORDER BY u.name"
      )
      dict = q.columns_dict

      expect(dict[:select]).to include("users.name")
      expect(dict[:join]).to include("users.id", "orders.user_id")
      expect(dict[:where]).to include("users.active")
    end

    it "omits empty clauses" do
      q = described_class.new("SELECT a FROM t")
      dict = q.columns_dict
      expect(dict).not_to have_key(:where)
      expect(dict).not_to have_key(:join)
    end
  end

  # ── output_columns ─────────────────────────────────────────────────

  describe "#output_columns" do
    it "returns column names and aliases" do
      q = described_class.new("SELECT a, b AS c FROM t")
      expect(q.output_columns).to eq(["a", "c"])
    end

    it "returns * for wildcard" do
      q = described_class.new("SELECT * FROM t")
      expect(q.output_columns).to include("*")
    end

    it "returns empty array for non-SELECT" do
      q = described_class.new("INSERT INTO t (a) VALUES (1)")
      expect(q.output_columns).to eq([])
    end
  end

  # ── columns_aliases ────────────────────────────────────────────────

  describe "#columns_aliases" do
    it "maps alias to source columns" do
      q = described_class.new(
        "SELECT a, b + c AS total FROM t"
      )
      aliases = q.columns_aliases
      expect(aliases).to have_key("total")
      expect(aliases["total"]).to include("b", "c")
    end
  end

  describe "#columns_aliases_names" do
    it "returns alias names" do
      q = described_class.new("SELECT a AS x, b AS y FROM t")
      expect(q.columns_aliases_names).to contain_exactly("x", "y")
    end
  end

  # ── with_names / with_queries ──────────────────────────────────────

  describe "#with_names" do
    it "extracts CTE names" do
      q = described_class.new(
        "WITH active_users AS (SELECT * FROM users WHERE active = true) " \
        "SELECT * FROM active_users"
      )
      expect(q.with_names).to eq(["active_users"])
    end

    it "returns empty array when no CTEs" do
      q = described_class.new("SELECT 1")
      expect(q.with_names).to eq([])
    end
  end

  describe "#with_queries" do
    it "regenerates CTE SQL body" do
      q = described_class.new(
        "WITH cte AS (SELECT id FROM users) SELECT * FROM cte"
      )
      expect(q.with_queries).to have_key("cte")
      expect(q.with_queries["cte"]).to match(/SELECT.*id.*FROM.*users/i)
    end
  end

  # ── limit_and_offset ───────────────────────────────────────────────

  describe "#limit_and_offset" do
    it "extracts LIMIT and OFFSET" do
      q = described_class.new("SELECT * FROM t LIMIT 50 OFFSET 100")
      expect(q.limit_and_offset).to eq([50, 100])
    end

    it "defaults offset to 0 when not specified" do
      q = described_class.new("SELECT * FROM t LIMIT 10")
      expect(q.limit_and_offset).to eq([10, 0])
    end

    it "returns nil for queries without LIMIT" do
      q = described_class.new("SELECT * FROM t")
      expect(q.limit_and_offset).to be_nil
    end
  end

  # ── values / values_dict ───────────────────────────────────────────

  describe "#values" do
    it "extracts values from INSERT" do
      q = described_class.new(
        "INSERT INTO users (name, age) VALUES ('Alice', 30)"
      )
      expect(q.values).to eq(["Alice", 30])
    end

    it "returns empty array for non-INSERT" do
      q = described_class.new("SELECT 1")
      expect(q.values).to eq([])
    end
  end

  describe "#values_dict" do
    it "maps columns to values" do
      q = described_class.new(
        "INSERT INTO users (name, age) VALUES ('Bob', 25)"
      )
      expect(q.values_dict).to eq({ "name" => "Bob", "age" => 25 })
    end

    it "auto-generates column names when not specified" do
      q = described_class.new(
        "INSERT INTO t VALUES (1, 'hello')"
      )
      expect(q.values_dict).to eq({
        "column_1" => 1,
        "column_2" => "hello"
      })
    end
  end

  # ── generalize ─────────────────────────────────────────────────────

  describe "#generalize" do
    it "replaces literals with placeholders" do
      q = described_class.new("SELECT * FROM t WHERE id = 42 AND name = 'Alice'")
      gen = q.generalize
      expect(gen).not_to include("42")
      expect(gen).not_to include("Alice")
      expect(gen).to match(/N|X/i)
    end
  end

  # ── ast ────────────────────────────────────────────────────────────

  describe "#ast" do
    it "returns the parsed AST Hash" do
      q = described_class.new("SELECT 1")
      expect(q.ast).to be_a(Hash)
      expect(q.ast).to have_key("Select")
    end
  end
end
