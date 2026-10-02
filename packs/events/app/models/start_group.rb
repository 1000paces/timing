class StartGroup < ApplicationRecord
  include BroadcastsEventChange
  belongs_to :event
  has_many :races, dependent: :restrict_with_error

  before_validation { self.finish_rule = finish_rule.deep_stringify_keys if finish_rule.is_a?(Hash) }

  validates :name, presence: true
  validate :finish_rule_shape

  private

  def finish_rule_shape
    rule = finish_rule.is_a?(Hash) ? finish_rule : {}
    case rule["type"]
    when "fixed_laps"
      errors.add(:finish_rule, "laps must be a positive integer") unless positive_int?(rule["laps"])
    when "timed"
      errors.add(:finish_rule, "target_duration_ms must be a positive integer") unless positive_int?(rule["target_duration_ms"])
    else
      errors.add(:finish_rule, "type must be fixed_laps or timed")
    end
  end

  def positive_int?(value) = value.is_a?(Integer) && value.positive?
end
