module RaceSimulator
  # Plain-text standings, for watching races before the ops console exists.
  module Table
    module_function

    def render(report)
      races = report.event.races.includes(:category).index_by(&:id)
      lines = []
      lines << "STALE (#{report.error})" if report.stale
      report.output.races.each do |result|
        name = races[result.race_id]&.name || result.race_id
        lines << "#{name} — #{result.state.to_s.tr('_', ' ')} — #{result.lap_count ? "#{result.lap_count} laps" : 'lap count not set'}"
        result.rows.each do |row|
          lines << format("%4s  %-5s %-22s %-9s %3d  %s", row.place || "-", row.bib, row.name, row.status, row.laps, clock(row.elapsed_ms))
        end
        lines << ""
      end
      open = report.output.suggestions.size
      lines << "#{open} open suggestion#{'s' unless open == 1}" if open.positive?
      lines.join("\n")
    end

    def clock(ms)
      return "" unless ms
      tenths = (ms / 100.0).round
      minutes, rest = tenths.divmod(600)
      hours, minutes = minutes.divmod(60)
      seconds = format("%04.1f", rest / 10.0)
      hours.positive? ? format("%d:%02d:%s", hours, minutes, seconds) : "#{minutes}:#{seconds}"
    end
  end
end
