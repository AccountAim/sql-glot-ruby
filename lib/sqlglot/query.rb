# frozen_string_literal: true

require "set"

module Sqlglot
  # High-level query metadata extraction, inspired by Python's sql-metadata.
  #
  # Parses SQL once via the Rust FFI, then walks the resulting AST Hash in
  # pure Ruby to extract tables, columns, aliases, subqueries, CTEs, etc.
  # All properties are lazy-evaluated and cached.
  #
  # @example
  #   q = Sqlglot::Query.new(
  #     "SELECT u.name, COUNT(o.id) AS cnt FROM users AS u " \
  #     "JOIN orders AS o ON u.id = o.user_id WHERE u.active = true",
  #     dialect: :postgres
  #   )
  #   q.query_type        # => :select
  #   q.tables            # => ["users", "orders"]
  #   q.tables_aliases    # => {"u" => "users", "o" => "orders"}
  #   q.columns           # => ["users.name", "orders.id", "users.id", ...]
  #   q.output_columns    # => ["name", "cnt"]
  #   q.columns_dict      # => {select: [...], join: [...], where: [...]}
  class Query
    # @param sql [String] the SQL query
    # @param dialect [Symbol, String, nil] the SQL dialect
    def initialize(sql, dialect: nil)
      @sql = sql
      @dialect = dialect
      reset_cache!
    end

    # @return [String] the original SQL string
    attr_reader :sql

    # ── AST access ─────────────────────────────────────────────────────

    # The parsed AST as a Ruby Hash.
    # @return [Hash]
    def ast
      @ast ||= Sqlglot.parse(@sql, dialect: @dialect)
    end

    # ── Query type ─────────────────────────────────────────────────────

    # The type of SQL statement.
    #
    # @return [Symbol] one of :select, :insert, :update, :delete,
    #   :create_table, :create_view, :drop_table, :drop_view,
    #   :alter_table, :truncate, :merge, :begin, :commit, :rollback,
    #   :explain, :use, :unknown
    def query_type
      @query_type ||= detect_query_type
    end

    # ── Tables ─────────────────────────────────────────────────────────

    # All table names referenced in the query, with CTE names excluded.
    #
    # @return [Array<String>]
    def tables
      @tables ||= extract_tables
    end

    # Map of table alias => real table name.
    #
    # @return [Hash{String => String}]
    def tables_aliases
      @tables_aliases ||= extract_tables_aliases
    end

    # ── Columns ────────────────────────────────────────────────────────

    # All column references, alias-resolved and table-qualified where
    # possible.
    #
    # @return [Array<String>]
    def columns
      @columns ||= extract_all_columns
    end

    # Columns grouped by the clause they appear in.
    #
    # @return [Hash{Symbol => Array<String>}]
    #   Keys: :select, :where, :join, :group_by, :order_by, :having,
    #         :insert, :update
    def columns_dict
      @columns_dict ||= extract_columns_dict
    end

    # The column names (or aliases) that the SELECT would produce.
    #
    # @return [Array<String>]
    def output_columns
      @output_columns ||= extract_output_columns
    end

    # ── Column aliases ─────────────────────────────────────────────────

    # Map of column alias => array of source columns.
    #
    # @return [Hash{String => Array<String>}]
    def columns_aliases
      @columns_aliases ||= extract_columns_aliases
    end

    # Just the alias names.
    #
    # @return [Array<String>]
    def columns_aliases_names
      columns_aliases.keys
    end

    # Which query clause each column alias appears in.
    #
    # @return [Hash{Symbol => Array<String>}]
    def columns_aliases_dict
      @columns_aliases_dict ||= extract_columns_aliases_dict
    end

    # ── CTEs (WITH clauses) ────────────────────────────────────────────

    # Names of CTE definitions.
    #
    # @return [Array<String>]
    def with_names
      @with_names ||= extract_with_names
    end

    # CTE name => regenerated SQL body.
    #
    # @return [Hash{String => String}]
    def with_queries
      @with_queries ||= extract_with_queries
    end

    # ── Subqueries ─────────────────────────────────────────────────────

    # Subquery alias => regenerated SQL body (from FROM / JOIN only).
    #
    # @return [Hash{String => String}]
    def subqueries
      @subqueries ||= extract_subqueries
    end

    # Just the subquery alias names.
    #
    # @return [Array<String>]
    def subqueries_names
      subqueries.keys
    end

    # ── LIMIT / OFFSET ─────────────────────────────────────────────────

    # @return [Array(Integer, Integer), nil] [limit, offset] or nil
    def limit_and_offset
      @limit_and_offset ||= extract_limit_and_offset
    end

    # ── INSERT values ──────────────────────────────────────────────────

    # Values from an INSERT statement.
    #
    # @return [Array]
    def values
      @values ||= extract_values
    end

    # Column => value pairs for INSERT.  Auto-generates column_N names
    # if the INSERT has no explicit column list.
    #
    # @return [Hash{String => Object}]
    def values_dict
      @values_dict ||= extract_values_dict
    end

    # ── Comments ───────────────────────────────────────────────────────

    # SQL comments found in the AST.
    #
    # @return [Array<String>]
    def comments
      @comments ||= extract_comments
    end

    # ── Normalization ──────────────────────────────────────────────────

    # Generalized SQL with literals replaced by placeholders.
    # Useful for query fingerprinting.
    #
    # @return [String]
    def generalize
      @generalize ||= build_generalized
    end

    private

    def reset_cache!
      @ast = nil
      @query_type = nil
      @tables = nil
      @tables_aliases = nil
      @columns = nil
      @columns_dict = nil
      @output_columns = nil
      @columns_aliases = nil
      @columns_aliases_dict = nil
      @with_names = nil
      @with_queries = nil
      @subqueries = nil
      @limit_and_offset = nil
      @values = nil
      @values_dict = nil
      @comments = nil
      @generalize = nil
    end

    # ── Query type detection ───────────────────────────────────────────

    QUERY_TYPE_MAP = {
      "Select"       => :select,
      "Insert"       => :insert,
      "Update"       => :update,
      "Delete"       => :delete,
      "CreateTable"  => :create_table,
      "CreateView"   => :create_view,
      "DropTable"    => :drop_table,
      "DropView"     => :drop_view,
      "AlterTable"   => :alter_table,
      "Truncate"     => :truncate,
      "Merge"        => :merge,
      "Begin"        => :begin,
      "Commit"       => :commit,
      "Rollback"     => :rollback,
      "Explain"      => :explain,
      "Use"          => :use,
    }.freeze

    def detect_query_type
      key = AstWalker.node_type(ast)
      QUERY_TYPE_MAP.fetch(key, :unknown)
    end

    # ── Statement body accessor ────────────────────────────────────────

    # The inner statement hash (e.g. the SelectStatement contents).
    def stmt
      @stmt ||= ast.values.first || {}
    end

    # ── Table extraction ───────────────────────────────────────────────

    def extract_tables
      cte_names = with_names.to_set
      raw = collect_table_refs(stmt)

      # Also collect tables referenced inside CTE bodies.
      (stmt["ctes"] || []).each do |cte|
        query_ast = cte["query"]
        next unless query_ast.is_a?(Hash)

        inner_stmt = query_ast.values.first
        raw.concat(collect_table_refs(inner_stmt)) if inner_stmt.is_a?(Hash)
      end

      raw.map { |t| t[:name] }.uniq.reject { |n| cte_names.include?(n) }
    end

    def extract_tables_aliases
      aliases = {}
      collect_table_refs(stmt).each do |t|
        aliases[t[:alias]] = t[:name] if t[:alias] && t[:alias] != t[:name]
      end
      aliases
    end

    # Collect all TableRef-like nodes from the statement.
    # Returns [{name:, alias:}, ...]
    def collect_table_refs(node)
      refs = []

      # FROM clause
      if (from = node["from"])
        refs.concat(table_refs_from_source(from["source"] || from))
      end

      # JOINs
      if (joins = node["joins"])
        joins.each do |join|
          source = join["table"] || join["source"] || join
          refs.concat(table_refs_from_source(source))
        end
      end

      # UPDATE target table
      if (table = node["table"])
        refs.concat(table_refs_from_source(table))
      end

      # INSERT target
      if node.is_a?(Hash) && query_type == :insert && node["table"]
        refs.concat(table_refs_from_source(node["table"]))
      end

      # DELETE FROM
      if (from_table = node["from_table"])
        refs.concat(table_refs_from_source(from_table))
      end

      # USING (DELETE ... USING ...)
      if (using = node["using"])
        Array(using).each { |u| refs.concat(table_refs_from_source(u)) }
      end

      refs
    end

    def table_refs_from_source(source)
      return [] unless source.is_a?(Hash)

      refs = []

      if source.key?("Table")
        t = source["Table"]
        name = build_table_name(t)
        refs << { name: name, alias: t["alias"] || name }
      elsif source.key?("name")
        # Direct table ref (not wrapped in "Table")
        name = build_table_name(source)
        refs << { name: name, alias: source["alias"] || name }
      elsif source.key?("Subquery")
        # Subquery in FROM -- skip the table name, it's a derived table
        alias_name = source["alias"]
        if alias_name
          refs << { name: alias_name, alias: alias_name }
        end
      end

      # Recurse into source if it has its own "source" (nested structure)
      if source.key?("source")
        refs.concat(table_refs_from_source(source["source"]))
      end

      refs
    end

    def build_table_name(t)
      parts = [t["catalog"], t["schema"] || t["db"], t["name"]].compact.reject(&:empty?)
      parts.join(".")
    end

    # ── Alias resolution helpers ───────────────────────────────────────

    # Reverse map: alias -> real table name.
    def alias_to_table
      @alias_to_table ||= begin
        map = {}
        collect_table_refs(stmt).each do |t|
          map[t[:alias]] = t[:name] if t[:alias]
        end
        map
      end
    end

    # Resolve a potentially-aliased table prefix to the real table name.
    def resolve_table(table_or_alias)
      return nil if table_or_alias.nil?

      alias_to_table[table_or_alias] || table_or_alias
    end

    # Qualify a column with its resolved table name.
    def qualify_column(name, table)
      resolved = resolve_table(table)
      if resolved && !resolved.empty?
        "#{resolved}.#{name}"
      else
        name
      end
    end

    # ── Column extraction ──────────────────────────────────────────────

    def extract_all_columns
      dict = columns_dict
      dict.values.flatten.uniq
    end

    def extract_columns_dict
      result = {}

      case query_type
      when :select
        result[:select]   = columns_from_select_list
        result[:where]    = columns_from_expr(stmt["where_clause"])
        result[:join]     = columns_from_joins
        result[:group_by] = columns_from_exprs(stmt["group_by"])
        result[:order_by] = columns_from_order_by
        result[:having]   = columns_from_expr(stmt["having"])
      when :insert
        result[:insert] = columns_from_insert
      when :update
        result[:update] = columns_from_update
        result[:where]  = columns_from_expr(stmt["where_clause"])
      when :delete
        result[:where] = columns_from_expr(stmt["where_clause"])
      end

      # Resolve aliases used in ORDER BY / GROUP BY / HAVING.
      col_alias_map = columns_aliases
      %i[order_by group_by having].each do |clause|
        next unless result[clause]

        result[clause] = result[clause].flat_map do |c|
          col_alias_map[c] || [c]
        end
      end

      result.reject { |_, v| v.nil? || v.empty? }
    end

    def columns_from_select_list
      items = stmt["columns"] || []
      cols = []

      items.each do |item|
        if item.is_a?(Hash) && item.key?("Expr")
          expr_data = item["Expr"]
          expr_node = expr_data["expr"] || expr_data
          cols.concat(columns_from_expr(expr_node))
        elsif item == "Wildcard" || (item.is_a?(Hash) && item.key?("Wildcard"))
          cols << "*"
        elsif item.is_a?(Hash) && item.key?("QualifiedWildcard")
          qw = item["QualifiedWildcard"]
          table = resolve_table(qw["table"] || qw["qualifier"])
          cols << "#{table}.*"
        end
      end

      cols.uniq
    end

    def columns_from_joins
      cols = []
      (stmt["joins"] || []).each do |join|
        condition = join["condition"] || join["on"]
        cols.concat(columns_from_expr(condition))
      end
      cols.uniq
    end

    def columns_from_order_by
      items = stmt["order_by"] || []
      cols = []
      items.each do |item|
        expr_node = item.is_a?(Hash) ? (item["expr"] || item) : item
        cols.concat(columns_from_expr(expr_node))
      end
      cols.uniq
    end

    def columns_from_insert
      (stmt["columns"] || []).map do |c|
        c.is_a?(String) ? c : (c["name"] || c.to_s)
      end
    end

    def columns_from_update
      assignments = stmt["assignments"] || stmt["set"] || []
      cols = []
      assignments.each do |a|
        if a.is_a?(Hash)
          col = a["column"] || a["target"]
          cols.concat(columns_from_expr(col)) if col
        end
      end
      cols.uniq
    end

    def columns_from_exprs(exprs)
      return [] unless exprs.is_a?(Array)

      cols = []
      exprs.each { |e| cols.concat(columns_from_expr(e)) }
      cols.uniq
    end

    # Recursively extract qualified column names from an expression node.
    def columns_from_expr(node)
      return [] if node.nil?

      cols = []

      case node
      when Hash
        if node.key?("Column")
          col = node["Column"]
          cols << qualify_column(col["name"], col["table"])
        elsif node.key?("QualifiedWildcard")
          qw = node["QualifiedWildcard"]
          table = resolve_table(qw["table"] || qw["qualifier"])
          cols << "#{table}.*"
        else
          node.each_value do |v|
            cols.concat(columns_from_expr(v))
          end
        end
      when Array
        node.each { |child| cols.concat(columns_from_expr(child)) }
      end

      cols
    end

    # ── Output columns ─────────────────────────────────────────────────

    def extract_output_columns
      return [] unless query_type == :select

      items = stmt["columns"] || []
      items.map do |item|
        if item.is_a?(Hash) && item.key?("Expr")
          expr_data = item["Expr"]
          # Use alias if present, else derive name from expression.
          if expr_data["alias"] && !expr_data["alias"].empty?
            expr_data["alias"]
          else
            name_from_expr(expr_data["expr"] || expr_data)
          end
        elsif item == "Wildcard" || (item.is_a?(Hash) && item.key?("Wildcard"))
          "*"
        elsif item.is_a?(Hash) && item.key?("QualifiedWildcard")
          qw = item["QualifiedWildcard"]
          "#{qw['table'] || qw['qualifier']}.*"
        else
          item.to_s
        end
      end
    end

    # Best-effort short name from an expression node.
    def name_from_expr(node)
      return node.to_s unless node.is_a?(Hash)

      if node.key?("Column")
        node["Column"]["name"]
      elsif node.key?("Function")
        fn = node["Function"]
        "#{fn['name']}(...)"
      else
        key = AstWalker.node_type(node)
        key || node.to_s
      end
    end

    # ── Column alias extraction ────────────────────────────────────────

    def extract_columns_aliases
      return {} unless query_type == :select

      aliases = {}
      (stmt["columns"] || []).each do |item|
        next unless item.is_a?(Hash) && item.key?("Expr")

        expr_data = item["Expr"]
        alias_name = expr_data["alias"]
        next if alias_name.nil? || alias_name.empty?

        # Walk the expression to find all referenced columns.
        source_cols = columns_from_expr(expr_data["expr"] || expr_data)
        aliases[alias_name] = source_cols unless source_cols.empty?
      end

      aliases
    end

    def extract_columns_aliases_dict
      return {} unless query_type == :select

      alias_names = columns_aliases_names.to_set
      result = {}

      # Check ORDER BY
      (stmt["order_by"] || []).each do |item|
        expr_node = item.is_a?(Hash) ? (item["expr"] || item) : item
        AstWalker.find_all(expr_node, "Column").each do |col|
          name = col["name"]
          (result[:order_by] ||= []) << name if alias_names.include?(name)
        end
      end

      # Check GROUP BY
      (stmt["group_by"] || []).each do |expr|
        AstWalker.find_all(expr, "Column").each do |col|
          name = col["name"]
          (result[:group_by] ||= []) << name if alias_names.include?(name)
        end
      end

      # Check HAVING
      if stmt["having"]
        AstWalker.find_all(stmt["having"], "Column").each do |col|
          name = col["name"]
          (result[:having] ||= []) << name if alias_names.include?(name)
        end
      end

      # The SELECT list itself
      alias_names.each do |name|
        (result[:select] ||= []) << name
      end

      result.transform_values!(&:uniq)
      result
    end

    # ── CTE extraction ─────────────────────────────────────────────────

    def extract_with_names
      (stmt["ctes"] || []).filter_map { |cte| cte["name"] || cte["alias"] }
    end

    def extract_with_queries
      result = {}
      (stmt["ctes"] || []).each do |cte|
        cte_name = cte["name"] || cte["alias"]
        query_ast = cte["query"]
        next unless cte_name && query_ast

        result[cte_name] = Sqlglot.generate(query_ast, dialect: @dialect)
      end
      result
    end

    # ── Subquery extraction ────────────────────────────────────────────

    def extract_subqueries
      result = {}

      # Subqueries in FROM
      if (from = stmt["from"])
        collect_subqueries_from_source(from["source"] || from, result)
      end

      # Subqueries in JOINs
      (stmt["joins"] || []).each do |join|
        source = join["table"] || join["source"] || join
        collect_subqueries_from_source(source, result)
      end

      result
    end

    def collect_subqueries_from_source(source, result)
      return unless source.is_a?(Hash)

      if source.key?("Subquery")
        alias_name = source["alias"]
        if alias_name
          sub_ast = source["Subquery"]
          # The subquery may be directly a Statement or boxed.
          sub_ast = sub_ast.values.first if sub_ast.is_a?(Hash) && sub_ast.size == 1 && !sub_ast.key?("Select")
          result[alias_name] = Sqlglot.generate(source["Subquery"], dialect: @dialect)
        end
      end

      collect_subqueries_from_source(source["source"], result) if source.key?("source")
    end

    # ── LIMIT / OFFSET extraction ──────────────────────────────────────

    def extract_limit_and_offset
      return nil unless query_type == :select

      limit_node  = stmt["limit"]
      offset_node = stmt["offset"]

      return nil unless limit_node

      limit  = node_to_int(limit_node)
      offset = offset_node ? node_to_int(offset_node) : 0

      return nil unless limit

      [limit, offset]
    end

    def node_to_int(node)
      return node if node.is_a?(Integer)

      if node.is_a?(Hash) && node.key?("Number")
        node["Number"].to_i
      elsif node.is_a?(Hash)
        # Try to find a Number anywhere in the node.
        nums = AstWalker.find_all(node, "Number")
        nums.first&.to_i
      else
        node.to_i
      end
    end

    # ── INSERT values extraction ───────────────────────────────────────

    def extract_values
      return [] unless query_type == :insert

      source = stmt["source"]
      return [] unless source.is_a?(Hash) && source.key?("Values")

      rows = source["Values"]
      return [] unless rows.is_a?(Array) && !rows.empty?

      # Take the first row of values.
      rows.first.map { |v| AstWalker.extract_value(v) }
    end

    def extract_values_dict
      return {} unless query_type == :insert

      vals = values
      return {} if vals.empty?

      col_names = stmt["columns"] || []
      col_names = col_names.map { |c| c.is_a?(String) ? c : (c["name"] || c.to_s) }

      # Auto-generate column names if not specified.
      if col_names.empty?
        col_names = vals.each_index.map { |i| "column_#{i + 1}" }
      end

      col_names.zip(vals).to_h
    end

    # ── Comment extraction ─────────────────────────────────────────────

    def extract_comments
      all_comments = []

      # Comments on the statement itself.
      if stmt["comments"].is_a?(Array)
        all_comments.concat(stmt["comments"])
      end

      # Walk the entire AST for Commented nodes.
      AstWalker.walk(ast) do |key, value, _|
        if key == "Commented" && value.is_a?(Hash)
          c = value["comment"] || value["comments"]
          all_comments.concat(Array(c))
        end
      end

      all_comments.uniq
    end

    # ── Query generalization ───────────────────────────────────────────

    def build_generalized
      generalized_ast = deep_generalize(ast)
      Sqlglot.generate(generalized_ast, dialect: @dialect)
    rescue Sqlglot::Error
      # If generation fails on the modified AST, fall back to regex.
      @sql
        .gsub(/'[^']*'/, "'X'")
        .gsub(/\b\d+(\.\d+)?\b/, "N")
    end

    # Recursively replace all literals in the AST with placeholder values.
    def deep_generalize(node)
      case node
      when Hash
        if node.key?("Number")
          { "Number" => "N" }
        elsif node.key?("StringLiteral")
          { "StringLiteral" => "X" }
        elsif node.key?("Boolean")
          { "Boolean" => node["Boolean"] } # keep booleans as-is
        else
          node.transform_values { |v| deep_generalize(v) }
        end
      when Array
        node.map { |v| deep_generalize(v) }
      else
        node
      end
    end
  end
end
