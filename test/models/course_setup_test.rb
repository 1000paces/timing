require "test_helper"

class CourseSetupTest < ActiveSupport::TestCase
  test "the format defaults from the discipline and can be overridden" do
    assert_equal "laps", create_event(discipline: "cyclocross").race_format
    assert_equal "course", create_event(discipline: "gravel").race_format
    assert_equal "course", create_event(discipline: "road", sub_discipline: "road_race").race_format
    assert_equal "laps", create_event(discipline: "road", sub_discipline: "criterium").race_format
    assert_equal "course", create_event(discipline: "mountain_bike", sub_discipline: "xc_marathon").race_format
    assert_equal "laps", create_event(discipline: "gravel", race_format: "laps").race_format
    assert create_event(discipline: "gravel").course?
  end

  test "the format must be laps or course" do
    event = Event.new(name: "X", date: Date.new(2026, 10, 18), discipline: "gravel", race_format: "relay")
    assert_not event.valid?
    assert_includes event.errors[:race_format], "is not included in the list"
  end

  test "checkpoints come back in course order and need a name and a unique position" do
    event = create_event(discipline: "gravel")
    event.checkpoints.create!(position: 2, name: "Aid 2", distance_km: 62)
    event.checkpoints.create!(position: 1, name: "Aid 1", distance_km: 30.5)
    assert_equal [ "Aid 1", "Aid 2" ], event.reload.checkpoints.map(&:name)
    assert_not event.checkpoints.build(position: 1, name: "Dup").valid?
    assert_not event.checkpoints.build(position: 3, name: "").valid?
    assert_not event.checkpoints.build(position: 3, name: "Neg", distance_km: -1).valid?
  end

  test "deleting an event deletes its checkpoints" do
    event = create_event(discipline: "gravel")
    event.checkpoints.create!(position: 1, name: "Aid 1")
    event.destroy!
    assert_equal 0, Checkpoint.count
  end
end
