# Gives every registration without a bib the lowest unused number in its
# race's range (or the event's, when the race has none). Bibs already set are
# never changed, so running it again assigns nothing.
class BibAssigner
  Result = Data.define(:assigned, :unfilled) # assigned: [[registration, bib]], unfilled: [message]

  def self.call(event) = new(event).call

  def initialize(event)
    @event = event
  end

  def call
    assigned = []
    unfilled = []
    Registration.transaction do
      used = @event.registrations.where.not(bib: nil).pluck(:bib).to_set { it.to_i }
      @event.races.sort_by { [it.scheduled_at_ms, it.name] }.each do |race|
        waiting = race.registrations.where(bib: nil).joins(:rider).order("riders.last_name", "riders.first_name", :id).to_a
        next if waiting.empty?

        range = race.bib_range
        free = range ? range.lazy.reject { used.include?(it) } : [].lazy
        waiting.each do |registration|
          number = free.first
          break unless number
          registration.update!(bib: number.to_s)
          used << number
          assigned << [registration, number.to_s]
        end
        left = waiting.count { it.bib.nil? }
        unfilled << unfilled_message(race, left, range) if left.positive?
      end
    end
    Result.new(assigned:, unfilled:)
  end

  private

  def unfilled_message(race, left, range)
    who = left == 1 ? "1 rider still needs" : "#{left} riders still need"
    why = range ? "range #{range.first}–#{range.last} is full" : "no bib range"
    "#{race.name}: #{who} a bib — #{why}"
  end
end
