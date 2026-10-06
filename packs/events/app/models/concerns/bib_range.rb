# Optional bib_from..bib_to on a race or an event. Ranges in one event must not
# overlap; a race without its own range draws from the event's.
module BibRange
  extend ActiveSupport::Concern

  included do
    validates :bib_from, :bib_to, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validate :bib_range_complete_and_ordered
    validate :bib_range_free
  end

  def own_bib_range = (bib_from..bib_to if bib_from && bib_to)

  private

  def bib_range_complete_and_ordered
    return if bib_from.nil? && bib_to.nil?
    return errors.add(:base, "Bib range needs both a first and a last bib") if bib_from.nil? || bib_to.nil?
    errors.add(:bib_to, "must be greater than or equal to bib from") if bib_to < bib_from
  end

  def bib_range_free
    mine = own_bib_range
    return unless mine && mine.size.positive? && errors.none?
    clash = other_bib_ranges.find { |_, range| range.cover?(mine.first) || range.cover?(mine.last) || mine.cover?(range.first) }
    errors.add(:base, "Bib range #{mine.first}–#{mine.last} overlaps #{clash[0]} (#{clash[1].first}–#{clash[1].last})") if clash
  end
end
