require "csv"

# Imports registrations from a CSV export. Rows are independent: a bad row is
# reported and skipped, the rest still import.
class RegistrationImport
  FIELDS = %w[first_name last_name gender birth_date ability_level team license_number bib race].freeze
  REQUIRED = %w[first_name last_name gender bib race].freeze
  RIDER_FIELDS = %w[first_name last_name gender ability_level team license_number].freeze

  RowMessage = Data.define(:row, :message)
  Result = Data.define(:created, :errors, :warnings)

  def self.call(event:, csv:, mapping: {}) = new(event, csv, mapping).call

  def initialize(event, csv, mapping)
    @event = event
    @csv = csv
    @mapping = FIELDS.to_h { [it, it] }.merge(mapping.to_h.transform_keys(&:to_s))
  end

  def call
    text = @csv.delete_prefix("\uFEFF")
    table = CSV.parse(text, headers: true, header_converters: ->(header) { header.to_s.strip })
    missing = REQUIRED.reject { table.headers.include?(@mapping[it]) }
    return Result.new(created: 0, errors: missing.map { RowMessage.new(row: 1, message: "missing column #{it}") }, warnings: []) if missing.any?

    races = @event.races.index_by { it.name.downcase }
    created = 0
    errors = []
    warnings = []
    table.each.with_index(2) do |row, number|
      next if row.fields.all?(&:blank?)

      value = ->(field) { row[@mapping[field]]&.strip.presence }
      race = races[value.("race").to_s.downcase]
      next errors << RowMessage.new(row: number, message: "unknown race #{value.('race')}") unless race

      attrs = RIDER_FIELDS.to_h { [it, value.(it)] }
      if (raw_date = value.("birth_date"))
        attrs["birth_date"] = parse_date(raw_date)
        next errors << RowMessage.new(row: number, message: "birth_date must be YYYY-MM-DD") unless attrs["birth_date"]
      end
      registration = RiderRegistrar.register(race:, bib: value.("bib"), rider_attrs: attrs)
      if registration.persisted?
        created += 1
        registration.eligibility_warnings.each { warnings << RowMessage.new(row: number, message: it) }
      else
        registration.errors.full_messages.each { errors << RowMessage.new(row: number, message: it) }
      end
    end
    Result.new(created:, errors:, warnings:)
  end

  private

  def parse_date(raw)
    Date.iso8601(raw)
  rescue Date::Error
    nil
  end
end
