require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup { @official = create_official(name: "Pat", role: "chief", pin: "1357") }

  test "signs in with name and PIN, shows and ends the session" do
    sign_in(@official, "1357")
    assert_response :created
    assert_equal({ "id" => @official.id, "name" => "Pat", "role" => "chief" }, response.parsed_body)
    get "/session"
    assert_response :ok
    delete "/session"
    assert_response :no_content
    get "/session"
    assert_response :unauthorized
  end

  test "wrong PIN and unknown or inactive officials are refused alike" do
    sign_in(@official, "0000")
    assert_response :unauthorized
    assert_equal "Name or PIN is incorrect", response.parsed_body["error"]
    @official.update!(active: false)
    sign_in(@official, "1357")
    assert_response :unauthorized
  end

  # Review Focus 1
  test "sixth attempt in a minute is rate limited even with the right PIN" do
    5.times { sign_in(@official, "0000") }
    sign_in(@official, "1357")
    assert_response :too_many_requests
  end

  test "rate limit cannot be bypassed with X-Forwarded-For" do
    5.times do |i|
      post "/session", params: { name: "Pat", pin: "0000" }.to_json,
                       headers: ApiHelpers::JSON_HEADERS.merge("X-Forwarded-For" => "203.0.113.#{i + 1}")
    end
    post "/session", params: { name: "Pat", pin: "1357" }.to_json,
                     headers: ApiHelpers::JSON_HEADERS.merge("X-Forwarded-For" => "203.0.113.6")
    assert_response :too_many_requests
  end

  test "unknown name is refused with the same message" do
    post "/session", params: { name: "Nobody", pin: "1357" }.to_json, headers: ApiHelpers::JSON_HEADERS
    assert_response :unauthorized
    assert_equal "Name or PIN is incorrect", response.parsed_body["error"]
  end

  test "signing in resets the session (no fixation)" do
    other = create_official(name: "Sam", role: "timer", pin: "9753")
    sign_in(@official, "1357")
    before = session.id.to_s
    assert before.present?
    sign_in(other, "9753")
    assert_response :created
    refute_equal before, session.id.to_s
  end

  test "cross-origin requests are refused" do
    post "/session", params: { name: "Pat", pin: "1357" }.to_json,
                     headers: ApiHelpers::JSON_HEADERS.merge("Origin" => "http://evil.example")
    assert_response :forbidden
  end

  test "origins listed in TIMING_ALLOWED_ORIGINS are accepted" do
    ENV["TIMING_ALLOWED_ORIGINS"] = "http://localhost:5173"
    post "/session", params: { name: "Pat", pin: "1357" }.to_json,
                     headers: ApiHelpers::JSON_HEADERS.merge("Origin" => "http://localhost:5173")
    assert_response :created
  ensure
    ENV.delete("TIMING_ALLOWED_ORIGINS")
  end
end
