# frozen_string_literal: true

module Sqlglot
  # Rails integration.  Loaded automatically when +Rails::Railtie+ is
  # defined (see +lib/sqlglot.rb+).
  #
  # @example config/application.rb
  #   config.sqlglot.default_dialect = :postgres
  class Railtie < Rails::Railtie
    config.sqlglot = ActiveSupport::OrderedOptions.new

    initializer "sqlglot.configure" do |app|
      cfg = app.config.sqlglot

      Sqlglot.configure do |c|
        c.default_dialect = cfg.default_dialect if cfg.respond_to?(:default_dialect) && cfg.default_dialect
      end
    end
  end
end
