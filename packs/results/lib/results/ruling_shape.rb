module Results
  # Defensive type check on ruling payloads (the database layer enforces the same
  # rules on write; this guards the engine against rows that predate or bypass it).
  module RulingShape
    KEYS = {
      "set_race_start" => %w[race_id at_ms],
      "set_lap_count" => %w[race_id laps],
      "flag_out" => %w[race_id at_ms],
      "assign_bib" => %w[capture_id bib],
      "void_capture" => %w[capture_id],
      "insert_capture" => %w[bib at_ms],
      "flag_finish" => %w[bib capture_id],
      "pull" => %w[bib at_ms],
      "dnf" => %w[bib],
      "dns" => %w[bib],
      "dsq" => %w[bib],
      "dismiss_suggestion" => %w[suggestion_key],
      "publish_results" => %w[race_id result_digest],
      "revert" => %w[ruling_id]
    }.freeze

    ID_KEYS = %w[race_id capture_id ruling_id suggestion_key result_digest].freeze

    module_function

    def valid?(ruling)
      keys = KEYS[ruling.kind]
      payload = ruling.payload
      return false unless keys && payload.is_a?(Hash)
      keys.all? { |key| valid_value?(key, payload[key]) }
    end

    def valid_value?(key, value)
      if key.end_with?("_ms") then value.is_a?(Integer)
      elsif key == "laps" then value.is_a?(Integer) && value > 0
      elsif key == "bib" || ID_KEYS.include?(key) then value.is_a?(String) && !value.strip.empty?
      else false
      end
    end
  end
end
