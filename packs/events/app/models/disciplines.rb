# Event disciplines, their sub-disciplines, and their defaults: whether races finish with the leader, and whether they ride laps or a course.
# age_next_year: the season crosses the year boundary (CX), so racing age is
# as of the end of the following year.
module Disciplines
  Sub = Data.define(:id, :label, :finish_with_leader, :course) do
    def initialize(course: false, **) = super
  end
  Discipline = Data.define(:id, :label, :finish_with_leader, :subs, :age_next_year, :course) do
    def initialize(age_next_year: false, course: false, **) = super
  end

  TABLE = [
    Discipline.new(id: "cyclocross", label: "Cyclocross", finish_with_leader: true, subs: [], age_next_year: true),
    Discipline.new(id: "mountain_bike", label: "Mountain bike", finish_with_leader: false, subs: [
      Sub.new(id: "xco", label: "XCO", finish_with_leader: false),
      Sub.new(id: "xcc", label: "XCC", finish_with_leader: true),
      Sub.new(id: "xc_marathon", label: "XC marathon", finish_with_leader: false, course: true),
      Sub.new(id: "enduro", label: "Enduro", finish_with_leader: false),
      Sub.new(id: "downhill", label: "Downhill", finish_with_leader: false)
    ]),
    Discipline.new(id: "road", label: "Road", finish_with_leader: false, subs: [
      Sub.new(id: "road_race", label: "Road race", finish_with_leader: false, course: true),
      Sub.new(id: "criterium", label: "Criterium", finish_with_leader: true),
      Sub.new(id: "time_trial", label: "Time trial", finish_with_leader: false),
      Sub.new(id: "hill_climb", label: "Hill climb", finish_with_leader: false)
    ]),
    Discipline.new(id: "gravel", label: "Gravel", finish_with_leader: false, subs: [], course: true),
    Discipline.new(id: "run", label: "Run", finish_with_leader: false, subs: [], course: true)
  ].freeze

  module_function

  def find(id) = TABLE.find { it.id == id }

  def valid?(discipline, sub)
    d = find(discipline)
    d && (sub.blank? || d.subs.any? { it.id == sub })
  end

  def default_finish_with_leader(discipline, sub)
    d = find(discipline) or return false
    d.subs.find { it.id == sub }&.finish_with_leader || (sub.blank? && d.finish_with_leader) || false
  end

  def default_age_next_year(discipline) = find(discipline)&.age_next_year || false

  # "course" (point to point / single loop) or "laps".
  def default_race_format(discipline, sub)
    d = find(discipline) or return "laps"
    course = sub.present? ? d.subs.find { it.id == sub }&.course : d.course
    course ? "course" : "laps"
  end
end
