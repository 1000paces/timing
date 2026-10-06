require "test_helper"

class BibAssignerTest < ActiveSupport::TestCase
  setup do
    @event = create_event
    @early = create_race(event: @event, category: "Early", scheduled_at_ms: 1_000, bib_from: 100, bib_to: 102)
    @late = create_race(event: @event, category: "Late", scheduled_at_ms: 2_000)
  end

  def racer(first, last) = create_racer(first_name: first, last_name: last)
  def entry(race, first, last, bib: nil) = register(race:, bib:, racer: racer(first, last))
  def bibs = @event.registrations.joins(:racer).order("racers.last_name", "racers.first_name").pluck("racers.last_name", :bib).to_h

  test "fills empty bibs from the race's range in last-name order, and from the event's range for other races" do
    @event.update!(bib_from: 1, bib_to: 50)
    entry(@early, "Zed", "Young")
    entry(@early, "Amy", "Adams")
    entry(@late, "Bo", "Brown")
    result = BibAssigner.call(@event)
    assert_equal({ "Adams" => "100", "Young" => "101", "Brown" => "1" }, bibs)
    assert_equal [%w[Adams 100], %w[Young 101], %w[Brown 1]], result.assigned.map { |reg, bib| [reg.racer.last_name, bib] }
    assert_empty result.unfilled
  end

  test "existing bibs are kept and a second run assigns nothing" do
    entry(@early, "Amy", "Adams", bib: "100")
    entry(@early, "Bo", "Brown")
    BibAssigner.call(@event)
    assert_equal({ "Adams" => "100", "Brown" => "101" }, bibs)
    assert_empty BibAssigner.call(@event).assigned
    assert_equal({ "Adams" => "100", "Brown" => "101" }, bibs)
  end

  # Review Focus 3
  test "a hand-typed bib from another race inside the range counts as used" do
    entry(@late, "Hand", "Typed", bib: "100")
    entry(@early, "Amy", "Adams")
    BibAssigner.call(@event)
    assert_equal "101", bibs["Adams"]
  end

  test "racers left over when a range is full, or there is no range, are reported" do
    %w[A B C D].each { entry(@early, it, "Early#{it}") }
    entry(@late, "Lo", "Late")
    result = BibAssigner.call(@event)
    assert_equal 3, result.assigned.size
    assert_equal ["Early Men: 1 racer still needs a bib — range 100–102 is full", "Late Men: 1 racer still needs a bib — no bib range"],
                 result.unfilled
    assert_nil bibs["EarlyD"]
  end

  test "check in and undo" do
    reg = entry(@early, "Amy", "Adams")
    reg.check_in!(at_ms: 123)
    assert_equal 123, reg.reload.checked_in_at_ms
    reg.undo_check_in!
    refute reg.reload.checked_in?
  end
end
