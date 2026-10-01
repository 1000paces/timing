require "test_helper"

class TimingModeTest < ActiveSupport::TestCase
  def with_env(vars)
    old = vars.keys.to_h { [it, ENV[it]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end

  test "defaults to hub mode on sqlite" do
    with_env("TIMING_MODE" => nil, "TIMING_DB" => nil) do
      assert TimingMode.hub?
      assert_equal "sqlite3", TimingMode.database_adapter
    end
  end

  test "cloud mode defaults to postgresql" do
    with_env("TIMING_MODE" => "cloud", "TIMING_DB" => nil) do
      assert TimingMode.cloud?
      assert_equal "postgresql", TimingMode.database_adapter
    end
  end

  test "TIMING_DB overrides the adapter" do
    with_env("TIMING_MODE" => "hub", "TIMING_DB" => "postgresql") do
      assert_equal "postgresql", TimingMode.database_adapter
    end
  end

  test "rejects unknown values" do
    with_env("TIMING_MODE" => "venue") { assert_raises(ArgumentError) { TimingMode.mode } }
    with_env("TIMING_MODE" => "hub", "TIMING_DB" => "mysql") { assert_raises(ArgumentError) { TimingMode.database_adapter } }
  end
end
