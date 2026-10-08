# The wave a Flag out from the Capture screen means: of the waves that have
# started and don't have their flag yet, the one that started last.
module CurrentWave
  module_function

  # { scheduled_at_ms:, start_at_ms:, races: [Race] } or nil.
  def for(event)
    results = StandingsService.report(event).output.races.index_by(&:race_id)
    waves = event.races.group_by { it.cohort.map(&:id).sort }.values.filter_map do |races|
      started = races.filter_map { results[it.id]&.start_at_ms }
      next if started.empty? || races.any? { results[it.id]&.flag_out_at_ms }
      { scheduled_at_ms: races.first.scheduled_at_ms, start_at_ms: started.min, races: races.sort_by(&:name) }
    end
    waves.max_by { it[:start_at_ms] }
  end
end
