require "test_helper"

class ConsoleCacheControlTest < ActiveSupport::TestCase
  APP = ->(_env) { [ 200, { "cache-control" => "public, max-age=31536000" }, [ "ok" ] ] }

  def cache_control(path)
    _status, headers, _body = ConsoleCacheControl.new(APP).call(Rack::MockRequest.env_for("http://hub.local#{path}"))
    headers["cache-control"]
  end

  test "the console page is always revalidated so a rebuild can't strand a cached copy" do
    assert_equal "no-cache", cache_control("/console")
    assert_equal "no-cache", cache_control("/console/")
    assert_equal "no-cache", cache_control("/console/index.html")
  end

  test "hashed console assets and other paths keep their caching" do
    assert_equal "public, max-age=31536000", cache_control("/console/assets/index-abc123.js")
    assert_equal "public, max-age=31536000", cache_control("/up")
  end
end
