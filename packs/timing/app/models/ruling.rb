class Ruling < ApplicationRecord
  include BroadcastsEventChange
  include AppendOnly

  # kind => payload keys that must be present (insert_capture may also carry checkpoint_id)
  KINDS = {
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

  # Kinds whose bib must be registered in the ruling's event. assign_bib may
  # target an unregistered bib (shown as unassigned on purpose).
  REGISTERED_BIB_KINDS = %w[insert_capture flag_finish pull dnf dns dsq].freeze
  ID_KEYS = %w[race_id capture_id ruling_id suggestion_key result_digest].freeze

  belongs_to :event

  before_validation do
    self.payload = payload.deep_stringify_keys if payload.is_a?(Hash)
    self.created_at_ms ||= (Time.now.to_r * 1000).to_i
  end

  validates :kind, inclusion: { in: KINDS.keys }
  validate :payload_has_required_keys
  validate :payload_types
  validate :bib_registered

  private

  def payload_has_required_keys
    return unless KINDS.key?(kind)
    missing = KINDS[kind] - (payload.is_a?(Hash) ? payload.keys : [])
    errors.add(:payload, "missing #{missing.join(', ')}") if missing.any?
  end

  def payload_types
    return unless KINDS.key?(kind) && payload.is_a?(Hash)
    KINDS[kind].each do |key|
      next unless payload.key?(key)
      message = type_error(key, payload[key])
      errors.add(:payload, "#{key} #{message}") if message
    end
  end

  def type_error(key, value)
    if key.end_with?("_ms") then "must be an integer" unless value.is_a?(Integer)
    elsif key == "laps" then "must be an integer greater than 0" unless value.is_a?(Integer) && value > 0
    elsif key == "bib" || ID_KEYS.include?(key) then "must be a non-empty string" unless value.is_a?(String) && value.strip.present?
    end
  end

  def bib_registered
    return unless REGISTERED_BIB_KINDS.include?(kind) && payload.is_a?(Hash) && errors[:payload].empty?
    return if Registration.exists?(event_id:, bib: payload["bib"])
    errors.add(:payload, "bib #{payload['bib']} is not registered in this event")
  end
end
