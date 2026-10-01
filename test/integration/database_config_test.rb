require "test_helper"

class DatabaseConfigTest < ActiveSupport::TestCase
  test "sqlite runs WAL with synchronous=FULL" do
    conn = ActiveRecord::Base.connection
    skip "running on #{conn.adapter_name}" unless conn.adapter_name == "SQLite"
    assert_equal "wal", conn.select_value("PRAGMA journal_mode")
    assert_equal 2, conn.select_value("PRAGMA synchronous") # 2 = FULL
  end
end
