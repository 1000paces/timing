class Ruling < ApplicationRecord
  include AppendOnly

  # kind => payload keys that must be present
  KINDS = {
    "set_group_start" => %w[start_group_id at_ms],
    "set_race_start" => %w[race_id at_ms],
    "set_lap_count" => %w[start_group_id laps],
    "assign_bib" => %w[capture_id bib],
    "void_capture" => %w[capture_id],
    "insert_capture" => %w[bib at_ms],
    "flag_finish" => %w[bib capture_id],
    "pull" => %w[bib at_ms],
    "dnf" => %w[bib],
    "dns" => %w[bib],
    "dsq" => %w[bib],
    "dismiss_suggestion" => %w[suggestion_key],
    "publish_results" => %w[race_id log_digest],
    "revert" => %w[ruling_id]
  }.freeze

  belongs_to :event

  before_validation do
    self.payload = payload.deep_stringify_keys if payload.is_a?(Hash)
    self.created_at_ms ||= (Time.now.to_r * 1000).to_i
  end

  validates :kind, inclusion: { in: KINDS.keys }
  validate :payload_has_required_keys

  private

  def payload_has_required_keys
    return unless KINDS.key?(kind)
    missing = KINDS[kind] - (payload.is_a?(Hash) ? payload.keys : [])
    errors.add(:payload, "missing #{missing.join(', ')}") if missing.any?
  end
end
