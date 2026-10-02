require "test_helper"

class HubTlsGateTest < ActiveSupport::TestCase
  APP = ->(_env) { [200, {}, ["ok"]] }

  def call(path, https: false, enabled: true)
    env = Rack::MockRequest.env_for("#{https ? 'https' : 'http'}://hub.local:3000#{path}")
    HubTlsGate.new(APP, enabled:).call(env)
  end

  test "plain HTTP only reaches onboarding and the health check" do
    assert_equal 200, call("/onboarding").first
    assert_equal 200, call("/onboarding/ca.crt").first
    assert_equal 200, call("/up").first
    status, _headers, body = call("/graphql")
    assert_equal 403, status
    assert_includes body.join, "/onboarding"
  end

  test "HTTPS passes, and the gate is off unless enabled" do
    assert_equal 200, call("/graphql", https: true).first
    assert_equal 200, call("/graphql", enabled: false).first
  end
end
