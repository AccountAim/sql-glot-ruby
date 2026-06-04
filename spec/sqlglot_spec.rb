# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sqlglot do
  describe ".version" do
    it "returns a semver string" do
      expect(Sqlglot.version).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe ".parse" do
    it "parses a simple SELECT into a Hash" do
      ast = Sqlglot.parse("SELECT a, b FROM t")
      expect(ast).to be_a(Hash)
      expect(ast).to have_key("Select")
    end

    it "accepts a dialect argument" do
      ast = Sqlglot.parse("SELECT `col` FROM t", dialect: :mysql)
      expect(ast).to have_key("Select")
    end

    it "raises ParseError on invalid SQL" do
      expect {
        Sqlglot.parse("NOT VALID SQL !!!")
      }.to raise_error(Sqlglot::ParseError)
    end
  end

  describe ".transpile" do
    it "transpiles LIMIT to TOP for T-SQL" do
      result = Sqlglot.transpile("SELECT * FROM t LIMIT 10",
                                 from: :mysql, to: :tsql)
      expect(result).to match(/TOP/i)
      expect(result).not_to match(/LIMIT/i)
    end

    it "transpiles NOW() across dialects" do
      result = Sqlglot.transpile("SELECT NOW()",
                                 from: :postgres, to: :tsql)
      # T-SQL uses GETDATE() or CURRENT_TIMESTAMP
      expect(result).to match(/GETDATE|CURRENT_TIMESTAMP/i)
    end

    it "defaults to ANSI when no dialect specified" do
      result = Sqlglot.transpile("SELECT 1")
      expect(result).to include("SELECT")
    end

    it "raises TranspileError on unparseable SQL" do
      expect {
        Sqlglot.transpile("THIS IS NOT SQL !!!")
      }.to raise_error(Sqlglot::TranspileError)
    end
  end

  describe ".generate" do
    it "roundtrips parse -> generate" do
      original = "SELECT a, b FROM t WHERE a > 1"
      ast = Sqlglot.parse(original)
      result = Sqlglot.generate(ast)
      # Normalised SQL should be semantically equivalent.
      expect(result.upcase).to include("SELECT")
      expect(result.upcase).to include("FROM")
    end

    it "accepts a dialect argument" do
      ast = Sqlglot.parse("SELECT * FROM t LIMIT 10")
      result = Sqlglot.generate(ast, dialect: :ansi)
      expect(result).to include("SELECT")
    end
  end

  describe ".configure" do
    after { Sqlglot.configure { |c| c.default_dialect = nil } }

    it "sets a default dialect" do
      Sqlglot.configure { |c| c.default_dialect = :postgres }
      # Should not raise even without explicit dialect.
      ast = Sqlglot.parse("SELECT 1")
      expect(ast).to be_a(Hash)
    end
  end

  describe Sqlglot::Dialect do
    describe ".resolve" do
      it "resolves symbols" do
        expect(Sqlglot::Dialect.resolve(:postgres)).to eq("postgres")
      end

      it "resolves aliases" do
        expect(Sqlglot::Dialect.resolve(:mssql)).to eq("tsql")
        expect(Sqlglot::Dialect.resolve("sqlserver")).to eq("tsql")
        expect(Sqlglot::Dialect.resolve("postgresql")).to eq("postgres")
      end

      it "returns nil for nil" do
        expect(Sqlglot::Dialect.resolve(nil)).to be_nil
      end

      it "raises on unknown dialect" do
        expect {
          Sqlglot::Dialect.resolve(:nosuchdialect)
        }.to raise_error(ArgumentError, /Unknown dialect/)
      end
    end
  end
end
