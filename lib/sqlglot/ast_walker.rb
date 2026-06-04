# frozen_string_literal: true

module Sqlglot
  # Generic helpers for traversing the JSON AST Hash returned by
  # {Sqlglot.parse}.
  #
  # The AST is a nested structure of Hashes and Arrays.  Statement and
  # expression types appear as single-key Hashes:
  #
  #   {"Column" => {"name" => "id", "table" => "users", ...}}
  #   {"Number" => "42"}
  #   {"BinaryOp" => {"left" => ..., "op" => "Eq", "right" => ...}}
  #
  # @api private
  module AstWalker
    module_function

    # Depth-first walk of the AST.  Yields every Hash node whose single
    # key is a recognised AST type name (capitalised, e.g. "Column").
    #
    # @param node [Hash, Array, Object] the AST subtree
    # @yieldparam type_key [String] the AST type name
    # @yieldparam value [Object] the contents of that node
    # @yieldparam node [Hash] the full single-key Hash
    def walk(node, &block)
      case node
      when Hash
        node.each do |key, value|
          # Yield if this looks like a typed AST node (capitalised key).
          if key.is_a?(String) && key =~ /\A[A-Z]/
            yield(key, value, node)
          end
          walk(value, &block)
        end
      when Array
        node.each { |child| walk(child, &block) }
      end
    end

    # Collect all nodes of a given AST type anywhere in the subtree.
    #
    # @param node [Hash, Array] the AST subtree
    # @param type_key [String] e.g. "Column", "Table", "Function"
    # @return [Array<Object>] the value side of each matching node
    def find_all(node, type_key)
      results = []
      walk(node) do |key, value, _|
        results << value if key == type_key
      end
      results
    end

    # Collect all Column references within an expression subtree.
    # Returns an array of +{name:, table:}+ hashes.
    #
    # @param node [Hash, Array]
    # @return [Array<Hash>]
    def extract_columns(node)
      find_all(node, "Column").map do |col|
        { name: col["name"], table: col["table"] }
      end
    end

    # Convert an AST literal node to a Ruby value.
    #
    #   {"Number" => "42"}         => 42
    #   {"Number" => "3.14"}       => 3.14
    #   {"StringLiteral" => "foo"} => "foo"
    #   {"Boolean" => true}        => true
    #   {"Null" => ...}            => nil
    #
    # @param node [Hash]
    # @return [Integer, Float, String, true, false, nil]
    def extract_value(node)
      return nil unless node.is_a?(Hash)

      if node.key?("Number")
        num = node["Number"]
        num.include?(".") ? num.to_f : num.to_i
      elsif node.key?("StringLiteral")
        node["StringLiteral"]
      elsif node.key?("Boolean")
        node["Boolean"]
      elsif node.key?("Null")
        nil
      else
        # Unknown literal type -- return the raw node.
        node
      end
    end

    # Return the single AST type key of a node, if it has exactly one
    # capitalised key (the standard pattern).
    #
    # @param node [Hash]
    # @return [String, nil]
    def node_type(node)
      return nil unless node.is_a?(Hash)

      node.each_key do |k|
        return k if k.is_a?(String) && k =~ /\A[A-Z]/
      end
      nil
    end

    # Unwrap nested single-key wrappers to get the inner payload.
    #
    # For example:
    #   {"Expr" => {"expr" => {"Column" => {...}}, "alias" => nil}}
    #
    # @param node [Hash]
    # @return [Hash]
    def unwrap(node)
      return node unless node.is_a?(Hash) && node.size == 1

      key = node.keys.first
      val = node.values.first
      val.is_a?(Hash) ? val : node
    end
  end
end
