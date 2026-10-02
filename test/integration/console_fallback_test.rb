require "test_helper"

class ConsoleFallbackTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Dir.mktmpdir
    @index = Pathname(@dir).join("index.html")
    File.write(@index, "<!doctype html><title>Timing console</title>")
    ConsoleController.index_path = @index
  end

  teardown do
    ConsoleController.index_path = nil
    FileUtils.remove_entry(@dir)
  end

  test "deep console links serve the console page, never cached" do
    get "/console/event/01a0fd27-794b-7839-a46f-5c115e45f703/starts"
    assert_response :ok
    assert_equal "text/html", response.media_type
    assert_includes response.body, "Timing console"
    assert_equal "no-cache", response.headers["cache-control"]
  end

  test "a missing build is a clear 404" do
    ConsoleController.index_path = Pathname(@dir).join("missing.html")
    get "/console/event/x"
    assert_response :not_found
    assert_includes response.body, "bin/rails console:build"
  end
end
