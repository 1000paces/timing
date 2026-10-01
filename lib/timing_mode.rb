# Selects hub vs cloud behavior and the database adapter. Loaded before
# database.yml is evaluated, so it must not depend on Rails.
module TimingMode
  MODES = %w[hub cloud].freeze
  ADAPTERS = %w[sqlite3 postgresql].freeze

  module_function

  def mode
    value = ENV.fetch("TIMING_MODE", "hub")
    raise ArgumentError, "TIMING_MODE must be one of #{MODES.join(', ')} (got #{value.inspect})" unless MODES.include?(value)
    value
  end

  def hub? = mode == "hub"
  def cloud? = mode == "cloud"

  def database_adapter
    value = ENV.fetch("TIMING_DB") { cloud? ? "postgresql" : "sqlite3" }
    raise ArgumentError, "TIMING_DB must be one of #{ADAPTERS.join(', ')} (got #{value.inspect})" unless ADAPTERS.include?(value)
    value
  end
end
