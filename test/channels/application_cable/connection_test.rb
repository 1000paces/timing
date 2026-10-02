require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects a signed-in official from the session cookie" do
    official = create_official
    cookies.encrypted["_timing_session"] = { value: { "official_id" => official.id } }
    connect
    assert_equal official, connection.current_official
  end

  test "rejects anonymous connections" do
    assert_reject_connection { connect }
  end
end
