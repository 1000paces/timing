# Registers racers for races. Racer and registration succeed or fail together
# (a savepoint, so one bad row inside a larger import leaves nothing behind).
class RacerRegistrar
  REGISTRATION_KEYS = %i[bib age external_category].freeze
  UPDATABLE_RACER_KEYS = %i[team city state birth_date].freeze

  # A new registration, creating the racer unless one with the same license exists.
  def self.register(race:, bib:, racer_attrs:, source: "manual", age: nil, external_category: nil)
    attrs = racer_attrs.to_h.transform_keys(&:to_sym)
    registration = nil
    Registration.transaction(requires_new: true) do
      license = attrs[:license_number].presence
      racer = (license && Racer.find_by(license_number: license)) || Racer.new(attrs)
      registration = Registration.new(race:, racer:, bib:, source:, age:, external_category:)
      if racer.persisted? && identity_mismatch?(racer, attrs)
        registration.errors.add(:base, "License #{license} belongs to #{racer.full_name}; check the license number")
        raise ActiveRecord::Rollback
      end
      racer_ok = racer.persisted? || racer.save
      registration.errors.merge!(racer.errors) unless racer_ok
      raise ActiveRecord::Rollback unless racer_ok && registration.save
    end
    registration
  end

  # Imports: update the racer's registration in this event if there is one
  # (matched by license, else by first and last name), otherwise register.
  # A blank bib or age never clears what's already there.
  def self.upsert(event:, race:, attrs:, source:)
    attrs = attrs.to_h.transform_keys(&:to_sym)
    racer_attrs = attrs.except(*REGISTRATION_KEYS)
    existing = match_in_event(event, racer_attrs)
    unless existing
      return register(race:, bib: attrs[:bib], racer_attrs:, source:, age: attrs[:age], external_category: attrs[:external_category])
    end

    Registration.transaction(requires_new: true) do
      racer = existing.racer
      racer.assign_attributes(racer_attrs.slice(*UPDATABLE_RACER_KEYS).compact_blank)
      racer.license_number ||= racer_attrs[:license_number].presence
      existing.assign_attributes(race:, external_category: attrs[:external_category],
                                 bib: attrs[:bib].presence || existing.bib, age: attrs[:age] || existing.age)
      racer_ok = racer.save
      existing.errors.merge!(racer.errors) unless racer_ok
      raise ActiveRecord::Rollback unless racer_ok && existing.save
    end
    existing
  end

  # The racer's registration in this event: by license, else by name — but a
  # name match whose racer holds a different license is someone else.
  def self.match_in_event(event, attrs)
    attrs = attrs.to_h.transform_keys(&:to_sym)
    scope = event.registrations.joins(:racer).includes(:racer)
    license = attrs[:license_number].presence
    by_license = license && scope.find_by(racers: { license_number: license })
    return by_license if by_license

    by_name = scope.where("LOWER(racers.first_name) = ? AND LOWER(racers.last_name) = ?",
                          attrs[:first_name].to_s.strip.downcase, attrs[:last_name].to_s.strip.downcase)
    by_name = by_name.where(racers: { license_number: [nil, ""] }) if license
    by_name.first
  end

  def self.identity_mismatch?(racer, attrs)
    %i[first_name last_name gender].any? do |field|
      incoming = attrs[field]
      incoming.present? && incoming.to_s.strip.casecmp?(racer[field].to_s.strip) == false
    end
  end
  private_class_method :identity_mismatch?
end
