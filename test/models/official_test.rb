require "test_helper"

class OfficialTest < ActiveSupport::TestCase
  test "PIN must be 4 to 8 digits and is stored as a digest" do
    official = create_official(pin: "123456")
    refute_equal "123456", official.pin_digest
    assert official.authenticate_pin("123456")
    refute official.authenticate_pin("654321")
    refute Official.new(name: "x", role: "chief", pin: "12").valid?
    refute Official.new(name: "x", role: "chief", pin: "12ab").valid?
  end

  test "roles are ordered timer < chief < admin" do
    chief = create_official(role: "chief")
    assert chief.at_least?("timer")
    assert chief.at_least?("chief")
    refute chief.at_least?("admin")
    refute Official.new(name: "x", role: "boss", pin: "1234").valid?
  end

  test "names are unique" do
    create_official(name: "Pat")
    refute Official.new(name: "Pat", role: "timer", pin: "1234").valid?
  end
end
