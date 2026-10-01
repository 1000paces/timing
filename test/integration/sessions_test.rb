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
