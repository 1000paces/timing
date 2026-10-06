require "csv"

# Imports registrations from a CSV export (BikeReg's promoter export, or our
# own column names). Two steps: analyze (columns and categories), then call
# with the official's column mapping and category choices. Rows are
# independent: a bad row is reported and skipped, the rest still import.
# Re-imports update matching riders and never remove anyone.
class RegistrationImport
  # field => header names recognised automatically (case-insensitive)
  HEADERS = {
    "first_name" => ["First Name", "first_name"],
    "last_name" => ["Last Name", "last_name"],
    "gender" => %w[Gender gender],
    "team" => %w[Team team],
    "license_number" => ["USAC License", "License", "license_number"],
    "age" => ["Age on Event Day", "Age", "age"],
    "birth_date" => ["Birth Date", "birth_date"],
    "city" => %w[City city],
    "state" => %w[State state],
    "bib" => %w[Bib bib],
    "category" => ["Category Entered / Merchandise Ordered", "Category Entered", "Race Category", "Category", "race"]
  }.freeze
  FIELDS = HEADERS.keys.freeze
  REQUIRED = %w[first_name last_name gender category].freeze
  RIDER_FIELDS = %w[first_name last_name team license_number city state].freeze
  GENDERS = { "m" => "M", "male" => "M", "f" => "F", "female" => "F", "x" => "X" }.freeze

  RowMessage = Data.define(:row, :message)
  CategoryRow = Data.define(:value, :count, :race_id, :skip)
  Analysis = Data.define(:headers, :mapping, :categories)
  Result = Data.define(:created, :updated, :skipped, :errors, :warnings, :not_in_file)

  def self.analyze(event:, csv:) = new(event, csv, nil).analyze

  # categories: { category value => { "race_id" => id } | { "skip" => true } }.
  # Values without a choice fall back to the saved mapping, then to a race of
  # the same name. A dry run reports what would happen and changes nothing.
  def self.call(event:, csv:, mapping: nil, categories: {}, dry_run: false) = new(event, csv, mapping).call(categories:, dry_run:)

  def initialize(event, csv, mapping)
    @event = event
    @table = CSV.parse(csv.delete_prefix("﻿"), headers: true, header_converters: ->(header) { header.to_s.strip })
    # A field the official set to blank is unmapped, even if a header would match.
    @mapping = auto_mapping.merge(mapping.to_h.transform_keys(&:to_s)).compact_blank
  end

  def analyze
    counts = rows.filter_map { |row, _| value(row, "category") }.tally
    categories = counts.map do |category, count|
      race_id, skip = suggestion(category)
      CategoryRow.new(value: category, count:, race_id:, skip: skip || false)
    end
    Analysis.new(headers: @table.headers.compact, mapping: @mapping, categories:)
  end

  def call(categories:, dry_run:)
    missing = REQUIRED.reject { @table.headers.include?(@mapping[it]) }
    if missing.any?
      return Result.new(created: 0, updated: 0, skipped: 0, errors: missing.map { RowMessage.new(row: 1, message: "missing column #{it}") },
                        warnings: [], not_in_file: [])
    end

    choices = categories.to_h.transform_values { it.to_h.transform_keys(&:to_s) }
    result = nil
    ActiveRecord::Base.transaction do
      result = import(choices)
      save_mappings(choices)
      raise ActiveRecord::Rollback if dry_run
    end
    result
  end

  private

  def rows = @table.each.with_index(2).reject { |row, _| row.fields.all?(&:blank?) }

  def value(row, field) = (header = @mapping[field]) && row[header]&.strip.presence

  def auto_mapping
    lookup = @table.headers.compact.index_by(&:downcase)
    HEADERS.filter_map { |field, names| (header = names.lazy.filter_map { lookup[it.downcase] }.first) && [field, header] }.to_h
  end

  def suggestion(category)
    saved = @event.category_mappings.find_by(external_category: category)
    return [saved.race_id, saved.skip] if saved
    [races_by_name[category.downcase]&.id, false]
  end

  def races_by_name = @races_by_name ||= @event.races.to_a.index_by { it.name.downcase }

  def target(choices, category)
    choice = choices[category]
    return (choice["skip"] ? :skip : @event.races.find_by(id: choice["race_id"])) if choice
    race_id, skip = suggestion(category)
    skip ? :skip : (race_id && @event.races.find(race_id))
  end

  def import(choices)
    counts = { created: 0, updated: 0, skipped: 0 }
    errors = []
    warnings = []
    touched = {} # registration id => row that updated it
    seen = {}
    rows.each do |row, number|
      category = value(row, "category")
      target = category && target(choices, category)
      next counts[:skipped] += 1 if target == :skip
      next errors << RowMessage.new(row: number, message: "category #{category} is not mapped to a race") unless target

      attrs, problem = row_attrs(row)
      next errors << RowMessage.new(row: number, message: problem) if problem

      key = attrs["license_number"] || "#{attrs['first_name']} #{attrs['last_name']}".downcase
      if (first_row = seen[key])
        next errors << RowMessage.new(row: number, message: "#{attrs['first_name']} #{attrs['last_name']} appears more than once in this file (row #{first_row})")
      end
      seen[key] = number

      if (earlier = RiderRegistrar.match_in_event(@event, attrs)&.then { touched[it.id] })
        next errors << RowMessage.new(row: number, message: "#{attrs['first_name']} #{attrs['last_name']} appears more than once in this file (row #{earlier})")
      end

      registration = RiderRegistrar.upsert(event: @event, race: target, attrs: attrs.merge("external_category" => category), source: "import")
      if registration.errors.any? || !registration.persisted?
        registration.errors.full_messages.each { errors << RowMessage.new(row: number, message: it) }
        next
      end
      touched[registration.id] = number
      counts[registration.previously_new_record? ? :created : :updated] += 1
      registration.eligibility_warnings.each { warnings << RowMessage.new(row: number, message: it) }
    end
    Result.new(**counts, errors:, warnings:, not_in_file: not_in_file(touched.keys))
  end

  # Returns [attrs, nil] or [nil, problem].
  def row_attrs(row)
    attrs = RIDER_FIELDS.to_h { [it, value(row, it)] }
    raw_gender = value(row, "gender")
    attrs["gender"] = GENDERS[raw_gender.to_s.downcase]
    return [nil, "gender #{raw_gender} must be M, F or X"] unless attrs["gender"]

    attrs["bib"] = value(row, "bib")
    if (raw_age = value(row, "age"))
      attrs["age"] = Integer(raw_age, 10, exception: false)
      return [nil, "age #{raw_age} must be a whole number"] unless attrs["age"]&.positive?
    end
    if (raw_date = value(row, "birth_date"))
      attrs["birth_date"] = parse_date(raw_date)
      return [nil, "birth_date must be YYYY-MM-DD"] unless attrs["birth_date"]
    end
    [attrs, nil]
  end

  def save_mappings(choices)
    choices.each do |category, choice|
      next unless choice["skip"] || @event.races.exists?(choice["race_id"])

      mapping = @event.category_mappings.find_or_initialize_by(external_category: category)
      mapping.update!(race_id: choice["skip"] ? nil : choice["race_id"], skip: choice["skip"] ? true : false)
    end
  end

  def not_in_file(touched)
    @event.registrations.where(source: "import").where.not(id: touched).includes(:rider, :race).map do |reg|
      "#{reg.rider.full_name} (#{[reg.bib && "bib #{reg.bib}", reg.race.name].compact.join(', ')})"
    end
  end

  def parse_date(raw)
    Date.iso8601(raw)
  rescue Date::Error
    nil
  end
end
