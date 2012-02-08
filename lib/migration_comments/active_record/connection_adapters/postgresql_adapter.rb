module MigrationComments::ActiveRecord::ConnectionAdapters
  module PostgreSQLAdapter
    def self.included(base)
      base.class_eval do
        alias_method_chain :create_table, :migration_comments
        alias_method_chain :add_column, :migration_comments
        alias_method_chain :change_column, :migration_comments
      end
    end

    def comments_supported?
      true
    end

    # Set a comment on a table
    def add_table_comment(table_name, comment_text)
      execute CommentDefinition.new(self, table_name, nil, comment_text).to_sql
    end

    # Set a comment on a column
    def add_column_comment(table_name, column_name, comment_text)
      execute CommentDefinition.new(self, table_name, column_name, comment_text).to_sql
    end

    def retrieve_table_comment(table_name)
      result = execute(table_comment_sql(table_name)).result
      result[0].nil? ? nil : result[0][0]
    end

    def retrieve_column_comment(table_name, column_name)
      retrieve_column_comments(table_name, column_name)[column_name.to_sym]
    end

    def retrieve_column_comments(table_name, *column_names)
      result = execute(column_comment_sql(table_name, *column_names)).result
      return {} if result.nil?
      return result.inject({}){|m, row| m[row[0].to_sym] = row[1]; m}
    end


    def create_table_with_migration_comments(table_name, options = {}, &block)
      local_table_definition = nil
      create_table_without_migration_comments(table_name, options) do |td|
        local_table_definition = td
        local_table_definition.comment options[:comment] if options.has_key?(:comment)
        block.call(td)
      end
      comments = local_table_definition.collect_comments(table_name)
      comments.each do |comment_definition|
        execute comment_definition.to_sql
      end
    end

    def add_column_with_migration_comments(table_name, column_name, type, options = {})
      add_column_without_migration_comments(table_name, column_name, type, options)
      if options[:comment]
        add_column_comment(table_name, column_name, options[:comment])
      end
    end

    def change_column_with_migration_comments(table_name, column_name, type, options = {})
      change_column_without_migration_comments(table_name, column_name, type, options)
      if options.keys.include?(:comment)
        add_column_comment(table_name, column_name, options[:comment])
      end
    end

    private
    def table_comment_sql(table_name)
      <<SQL
SELECT d.description FROM (
#{table_oids(table_name)}) tt
JOIN pg_catalog.pg_description d
  ON tt.oid = d.objoid AND tt.tableoid = d.classoid AND d.objsubid = 0;
SQL
    end

    def column_comment_sql(table_name, *column_names)
      col_matcher_sql = column_names.empty? ? "" : " a.attname IN (#{column_names.map{|c_name| "'#{c_name}'"}.join(',')}) AND "
      <<SQL
SELECT a.attname, pg_catalog.col_description(a.attrelid, a.attnum)
FROM pg_catalog.pg_attribute a
JOIN (
#{table_oids(table_name)}) tt
  ON tt.oid = a.attrelid
WHERE #{col_matcher_sql} a.attnum > 0 AND NOT a.attisdropped;
SQL
    end

    def table_oids(table_name)
      <<SQL
SELECT c.oid, c.tableoid
FROM pg_catalog.pg_class c
WHERE c.relname = '#{table_name}'
  AND c.relkind = 'r'
  AND pg_catalog.pg_table_is_visible(c.oid)
SQL
    end
  end
end
