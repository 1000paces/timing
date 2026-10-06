# Registers riders for races. Rider and registration succeed or fail together
# (a savepoint, so one bad row inside a larger import leaves nothing behind).
class RiderRegistrar
  REGISTRATION_KEYS = %i[bib age external_category].freeze
  UPDATABLE_RIDER_KEYS = %i[team city state birth_date].freeze

  # A new registration, creating the rider unless one with the same license exists.
  def self.register(race:, bib:, rider_attrs:, source: "manual", age: nil, external_category: nil)
    attrs = rider_attrs.to_h.transform_keys(&:to_sym)
    registration = nil
    Registration.transaction(requires_new: true) do
      license = attrs[:license_number].presence
      rider = (license && Rider.find_by(license_number: license)) || Rider.new(attrs)
      registration = Registration.new(race:, rider:, bib:, source:, age:, external_category:)
      if rider.persisted? && identity_mismatch?(rider, attrs)
        registration.errors.add(:base, "License #{license} belongs to #{rider.full_name}; check the license number")
        raise ActiveRecord::Rollback
      end
      rider_ok = rider.persisted? || rider.save
      registration.errors.merge!(rider.errors) unless rider_ok
      raise ActiveRecord::Rollback unless rider_ok && registration.save
    end
    registration
  end

  # Imports: update the rider's registration in this event if there is one
  # (matched by license, else by first and last name), otherwise register.
  # A blank bib or age never clears what's already there.
  def self.upsert(event:, race:, attrs:, source:)
    attrs = attrs.to_h.transform_keys(&:to_sym)
    rider_attrs = attrs.except(*REGISTRATION_KEYS)
    existing = find_in_event(event, rider_attrs)
    unless existing
      return register(race:, bib: attrs[:bib], rider_attrs:, source:, age: attrs[:age], external_category: attrs[:external_category])
    end

    Registration.transaction(requires_new: true) do
      rider = existing.rider
      rider.assign_attributes(rider_attrs.slice(*UPDATABLE_RIDER_KEYS).compact_blank)
      rider.license_number ||= rider_attrs[:license_number].presence
      existing.assign_attributes(race:, external_category: attrs[:external_category],
                                 bib: attrs[:bib].presence || existing.bib, age: attrs[:age] || existing.age)
      rider_ok = rider.save
      existing.errors.merge!(rider.errors) unless rider_ok
      raise ActiveRecord::Rollback unless rider_ok && existing.save
    end
    existing
  end

  def self.find_in_event(event, attrs)
    scope = event.registrations.joins(:rider).includes(:rider)
    license = attrs[:license_number].presence
    (license && scope.find_by(riders: { license_number: license })) ||
      scope.where("LOWER(riders.first_name) = ? AND LOWER(riders.last_name) = ?",
                  attrs[:first_name].to_s.strip.downcase, attrs[:last_name].to_s.strip.downcase).first
  end
  private_class_method :find_in_event

  def self.identity_mismatch?(rider, attrs)
    %i[first_name last_name gender].any? do |field|
      incoming = attrs[field]
      incoming.present? && incoming.to_s.strip.casecmp?(rider[field].to_s.strip) == false
    end
  end
  private_class_method :identity_mismatch?
end
