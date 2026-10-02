# Event disciplines, their sub-disciplines, and whether races finish with the
# leader by default (CX, XCC and crits do; XCO, marathon, road races don't).
module Disciplines
  Sub = Data.define(:id, :label, :finish_with_leader)
  Discipline = Data.define(:id, :label, :finish_with_leader, :subs)

  TABLE = [
    Discipline.new(id: "cyclocross", label: "Cyclocross", finish_with_leader: true, subs: []),
    Discipline.new(id: "mountain_bike", label: "Mountain bike", finish_with_leader: false, subs: [
      Sub.new(id: "xco", label: "XCO", finish_with_leader: false),
      Sub.new(id: "xcc", label: "XCC", finish_with_leader: true),
      Sub.new(id: "xc_marathon", label: "XC marathon", finish_with_leader: false),
      Sub.new(id: "enduro", label: "Enduro", finish_with_leader: false),
      Sub.new(id: "downhill", label: "Downhill", finish_with_leader: false)
    ]),
    Discipline.new(id: "road", label: "Road", finish_with_leader: false, subs: [
      Sub.new(id: "road_race", label: "Road race", finish_with_leader: false),
      Sub.new(id: "criterium", label: "Criterium", finish_with_leader: true),
      Sub.new(id: "time_trial", label: "Time trial", finish_with_leader: false),
      Sub.new(id: "hill_climb", label: "Hill climb", finish_with_leader: false)
    ]),
    Discipline.new(id: "gravel", label: "Gravel", finish_with_leader: false, subs: []),
    Discipline.new(id: "run", label: "Run", finish_with_leader: false, subs: [])
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
end
